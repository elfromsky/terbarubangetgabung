import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'realtime DTO normalizes nested Firebase map without parsing numbers',
    () {
      final dto = mapRealtimeMonitoringDataToDto({
        'environment': {'temperature': '28.5', 'humidity': 60},
        'power': {'voltage': '220', 'energy': 12.5},
      });

      expect(dto.environment['temperature'], '28.5');
      expect(dto.power['voltage'], '220');
      expect(dto.power['energy'], 12.5);
    },
  );

  test('realtime DTO empty fallback maps to empty entity', () {
    final dto = mapRealtimeMonitoringDataToDto('invalid');
    final entity = mapRealtimeMonitoringDtoToEntity(dto);

    expect(entity.mcb1.energy, 0);
    expect(entity.sensorData.temperature, 0);
  });

  test(
    'sensor DTO supports aliases and entity mapper normalizes invalid number',
    () {
      final dto = mapRealtimeSensorDataToDto({
        'suhu': '26.5',
        'kelembapan': 'invalid',
        'connected': true,
      });
      final entity = mapSensorDataDtoToEntity(dto);

      expect(entity.temperature, 26.5);
      expect(entity.humidity, 0);
      expect(entity.connected, isTrue);
    },
  );
}
