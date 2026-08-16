import 'package:esh/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase-specific identity and custom-claim loading.
///
/// Owns Firebase initialization, anonymous sign-in, and ID-token/claim
/// retrieval. It contains no authorization policy: whether the loaded claims
/// unlock the Flutter app is decided by `AuthGateController`.
class FirebaseClaims {
  bool _initialized = false;

  /// Initializes Firebase at most once per process.
  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    _initialized = true;
  }

  /// The UID of the current Firebase identity, or null if none exists yet.
  Future<String?> currentUid() async {
    try {
      await ensureInitialized();
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Loads the current identity's custom claims.
  ///
  /// Reuses the existing signed-in user; only signs in anonymously when no
  /// Firebase user exists. Returns `null` when no verdict can be obtained
  /// (for example a transient network/auth failure), otherwise the claims map
  /// (which may be empty).
  Future<Map<String, dynamic>?> loadClaims({
    required bool forceClaimRefresh,
  }) async {
    try {
      await ensureInitialized();

      final auth = FirebaseAuth.instance;
      var user = auth.currentUser;
      if (user == null) {
        final credential = await auth.signInAnonymously();
        user = credential.user;
      }
      if (user == null) {
        return null;
      }

      final token = await user.getIdTokenResult(forceClaimRefresh);
      return token.claims;
    } catch (_) {
      return null;
    }
  }
}
