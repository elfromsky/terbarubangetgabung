class CanonicalHistoryDto {
  final String id;
  final dynamic timestamp;
  final Map<String, dynamic> power;
  final Map<String, dynamic> environment;

  const CanonicalHistoryDto({
    required this.id,
    required this.timestamp,
    required this.power,
    required this.environment,
  });
}
