/// Pure custom-claim evaluation used by the Firebase bootstrap gate.
///
/// This file intentionally has no dependency on `firebase_auth` so the claim
/// contract and the foreground-refresh decision can be unit-tested without a
/// live backend.
library;

/// A device is trusted when its ID token carries `owner == true` or
/// `controller == true`.
///
/// Any other value (a missing claim, `false`, or a non-boolean value) is
/// rejected, so authorization fails closed by construction.
bool hasTrustedDeviceClaim(Map<String, dynamic>? claims) {
  return claims?['owner'] == true || claims?['controller'] == true;
}

/// Whether a Firebase identity is authorized to run the Flutter household
/// application.
///
/// The Flutter app must be able to read telemetry AND write `/commands` AND
/// create Firestore `sensorLogs`. The rules reserve command writes and
/// `sensorLogs` creation for `owner` alone, so `controller == true` by itself
/// is NOT sufficient to unlock the operational app.
///
/// Any other value (a missing claim, `false`, or a non-boolean value) is
/// rejected, so authorization fails closed by construction.
bool hasOwnerClaim(Map<String, dynamic>? claims) {
  return claims?['owner'] == true;
}

/// The result of a successful claim (re-)evaluation.
enum DeviceTrust { trusted, untrusted }

/// Maps freshly loaded ID-token claims to a trust verdict.
///
/// Returns `null` when the claims could not be loaded (for example a transient
/// network failure). A `null` result means "keep the current state", so an
/// already-trusted device is never bounced to an error screen by a momentary
/// loss of connectivity.
DeviceTrust? revalidateTrust(Map<String, dynamic>? claims) {
  if (claims == null) {
    return null;
  }
  return hasTrustedDeviceClaim(claims)
      ? DeviceTrust.trusted
      : DeviceTrust.untrusted;
}
