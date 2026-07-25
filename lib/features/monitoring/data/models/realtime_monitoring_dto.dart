class RealtimeMonitoringDto {
  final Map<String, dynamic> environment;
  final Map<String, dynamic> power;

  const RealtimeMonitoringDto({required this.environment, required this.power});

  factory RealtimeMonitoringDto.empty() {
    return const RealtimeMonitoringDto(environment: {}, power: {});
  }
}
