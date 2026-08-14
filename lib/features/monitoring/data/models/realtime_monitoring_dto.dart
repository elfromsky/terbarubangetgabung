class RealtimeMonitoringDto {
  final Map<String, dynamic> environment;
  final Map<String, dynamic> power;
  final int? unixTime;
  final int? environmentSampledAtEpochSeconds;
  final int? powerSampledAtEpochSeconds;

  const RealtimeMonitoringDto({
    required this.environment,
    required this.power,
    this.unixTime,
    this.environmentSampledAtEpochSeconds,
    this.powerSampledAtEpochSeconds,
  });

  factory RealtimeMonitoringDto.empty() {
    return const RealtimeMonitoringDto(
      environment: {},
      power: {},
      unixTime: null,
      environmentSampledAtEpochSeconds: null,
      powerSampledAtEpochSeconds: null,
    );
  }
}
