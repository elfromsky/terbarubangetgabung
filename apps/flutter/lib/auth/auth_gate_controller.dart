import 'package:esh/auth/device_claim.dart';
import 'package:flutter/foundation.dart';

/// Loads the current Firebase identity's custom claims.
///
/// Return `null` when no verdict can be obtained (for example a transient
/// network or auth failure). Return a claims map (possibly empty) when a
/// verdict was obtained. This distinction matters: a `null` result means "no
/// authoritative verdict", whereas an empty map means "authenticated but the
/// required claim is absent".
typedef ClaimLoader =
    Future<Map<String, dynamic>?> Function({required bool forceClaimRefresh});

/// Resolves the current Firebase UID for display on the enrollment screen.
typedef UidProvider = Future<String?> Function();

/// The authorization state observed by the bootstrap gate.
enum AuthGateStatus {
  /// Firebase/claims are being established or refreshed.
  loading,

  /// The current identity carries the required owner claim.
  trusted,

  /// The current identity is authenticated but lacks the owner claim.
  unprovisioned,

  /// No verdict could be obtained (auth/network failure) during startup or a
  /// manual retry.
  error,
}

/// Pure authorization state machine for the Firebase bootstrap gate.
///
/// It owns no Firebase SDK. Claim loading is injected so the transitions are
/// unit-testable without a live backend.
///
/// Semantics:
/// - `bootstrap()` is the initial, fail-closed startup. A null verdict or a
///   missing owner claim never enters `trusted`.
/// - `retry()` is the manual fallback and always force-refreshes the token.
/// - `revalidate()` runs on foreground/resume and force-refreshes the token
///   without flashing `loading`; a transient failure preserves the prior
///   verdict, while an authoritative "claim absent" verdict demotes to
///   `unprovisioned`.
class AuthGateController extends ChangeNotifier {
  AuthGateController({required ClaimLoader loadClaims, UidProvider? loadUid})
    : _loadClaims = loadClaims,
      _loadUid = loadUid;

  final ClaimLoader _loadClaims;
  final UidProvider? _loadUid;

  AuthGateStatus _status = AuthGateStatus.loading;
  String? _uid;

  bool _booting = false;
  int _generation = 0;

  AuthGateStatus get status => _status;

  /// The Firebase UID of the current (anonymous) identity, for the enrollment
  /// screen. Populated after an `unprovisioned` verdict.
  String? get uid => _uid;

  /// Whether a bootstrap/retry operation is currently in flight.
  bool get isBusy => _booting;

  /// Initial startup. Fails closed: only an authoritative owner verdict enters
  /// `trusted`.
  Future<void> bootstrap() => _boot(force: false);

  /// Manual retry. Force-refreshes the token so a newly-assigned owner claim
  /// is picked up immediately.
  Future<void> retry() => _boot(force: true);

  /// Foreground/resume revalidation. Force-refreshes the token without
  /// flashing `loading`; preserves the prior verdict on a transient failure.
  Future<void> revalidate() async {
    if (_booting || _status == AuthGateStatus.loading) {
      return;
    }

    final generation = _generation;
    final bool? verdict;
    try {
      verdict = await _evaluate(force: true);
    } catch (_) {
      return;
    }

    if (generation != _generation || _booting) {
      return;
    }
    if (verdict == null) {
      return;
    }

    await _applyVerdict(verdict);
  }

  Future<void> _boot({required bool force}) async {
    if (_booting) {
      return;
    }
    _booting = true;
    _generation += 1;
    final generation = _generation;

    _status = AuthGateStatus.loading;
    notifyListeners();

    bool? verdict;
    try {
      verdict = await _evaluate(force: force);
    } catch (_) {
      verdict = null;
    }

    if (generation != _generation) {
      return;
    }

    _booting = false;
    if (verdict == null) {
      _status = AuthGateStatus.error;
      notifyListeners();
    } else {
      await _applyVerdict(verdict);
    }
  }

  /// Returns `null` for "no verdict", otherwise the owner verdict.
  Future<bool?> _evaluate({required bool force}) async {
    final claims = await _loadClaims(forceClaimRefresh: force);
    if (claims == null) {
      return null;
    }
    return hasOwnerClaim(claims);
  }

  Future<void> _applyVerdict(bool trusted) async {
    if (trusted) {
      _status = AuthGateStatus.trusted;
    } else {
      _status = AuthGateStatus.unprovisioned;
      await _refreshUid();
    }
    notifyListeners();
  }

  Future<void> _refreshUid() async {
    final provider = _loadUid;
    if (provider == null) {
      return;
    }
    try {
      _uid = await provider();
    } catch (_) {
      _uid = null;
    }
  }
}
