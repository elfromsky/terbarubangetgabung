import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/sensor_data_dto.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

McbDataCollection mapRealtimeMonitoringDtoToEntity(RealtimeMonitoringDto dto) {
  return McbDataCollection(
    mcb1: McbData(
      connected: dto.power['connected'] == true,
      voltage: parseFirebaseDouble(dto.power['voltage']),
      current: parseFirebaseDouble(dto.power['current']),
      power: parseFirebaseDouble(dto.power['power']),
      energy: parseFirebaseDouble(dto.power['energy']),
    ),
    sensorData: SensorData(
      temperature: parseFirebaseDouble(dto.environment['temperature']),
      humidity: parseFirebaseDouble(dto.environment['humidity']),
      connected: dto.environment['connected'] == true,
    ),
  );
}

SensorData mapSensorDataDtoToEntity(SensorDataDto dto) {
  return SensorData(
    temperature: parseFirebaseDouble(dto.temperature),
    humidity: parseFirebaseDouble(dto.humidity),
    connected: dto.connected,
  );
}
