import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/sensor_data_dto.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

McbDataCollection mapRealtimeMonitoringDtoToEntity(RealtimeMonitoringDto dto) {
  final environmentConnected = dto.environment['connected'] == true;
  return McbDataCollection(
    mcb1: McbData(
      connected: dto.power['connected'] == true,
      voltage: parseFirebaseDouble(dto.power['voltage']),
      current: parseFirebaseDouble(dto.power['current']),
      power: parseFirebaseDouble(dto.power['power']),
      energy: parseFirebaseDouble(dto.power['energy']),
    ),
    sensorData: SensorData(
      temperature: environmentConnected
          ? parseFirebaseDouble(dto.environment['temperature'])
          : 0,
      humidity: environmentConnected
          ? parseFirebaseDouble(dto.environment['humidity'])
          : 0,
      connected: environmentConnected,
    ),
  );
}

SensorData mapSensorDataDtoToEntity(SensorDataDto dto) {
  return SensorData(
    temperature: dto.connected ? parseFirebaseDouble(dto.temperature) : 0,
    humidity: dto.connected ? parseFirebaseDouble(dto.humidity) : 0,
    connected: dto.connected,
  );
}
