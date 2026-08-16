/// Canonical Firestore `sensorLogs` document schema.
///
/// Contract:
/// - `timestamp`: Firestore Timestamp or epoch millis.
/// - `power`: map with `connected`, `voltage`, `current`, `power`, `energy`,
///   optional `sampled_at`.
/// - `environment`: map with `connected`, `temperature`, `humidity`,
///   optional `sampled_at`.
/// - `derived`: optional map with computed values such as `estimatedCost`
///   and `estimatedEmission`.
class CanonicalHistoryDto {
  final String id;
  final dynamic timestamp;
  final Map<String, dynamic> power;
  final Map<String, dynamic> environment;
  final Map<String, dynamic>? derived;

  const CanonicalHistoryDto({
    required this.id,
    required this.timestamp,
    required this.power,
    required this.environment,
    this.derived,
  });
}
