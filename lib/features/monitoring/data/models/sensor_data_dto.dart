class SensorDataDto {
  final dynamic temperature;
  final dynamic humidity;
  final bool connected;

  const SensorDataDto({
    required this.temperature,
    required this.humidity,
    required this.connected,
  });

  factory SensorDataDto.empty() {
    return const SensorDataDto(
      temperature: null,
      humidity: null,
      connected: false,
    );
  }
}
