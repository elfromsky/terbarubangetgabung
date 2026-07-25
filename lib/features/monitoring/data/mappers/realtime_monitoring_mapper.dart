import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/sensor_data_dto.dart';

RealtimeMonitoringDto mapRealtimeMonitoringDataToDto(dynamic value) {
  if (value is! Map) return RealtimeMonitoringDto.empty();

  final root = normalizeFirebaseMap(value);
  final environment = root['environment'];
  final power = root['power'];
  return RealtimeMonitoringDto(
    environment: environment is Map
        ? normalizeFirebaseMap(environment)
        : <String, dynamic>{},
    power: power is Map ? normalizeFirebaseMap(power) : <String, dynamic>{},
  );
}

SensorDataDto mapRealtimeSensorDataToDto(dynamic value) {
  if (value is! Map) return SensorDataDto.empty();

  try {
    final map = Map<String, dynamic>.from(value);
    return SensorDataDto(
      temperature: map['temperature'] ?? map['temp'] ?? map['suhu'],
      humidity: map['humidity'] ?? map['hum'] ?? map['kelembapan'],
      connected: map['connected'] == true,
    );
  } catch (_) {
    return SensorDataDto.empty();
  }
}
