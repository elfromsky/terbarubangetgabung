import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'realtime DTO normalizes nested Firebase map without parsing numbers',
    () {
      final dto = mapRealtimeMonitoringDataToDto({
        'unix_time': 2000000000,
        'environment': {
          'temperature': '28.5',
          'humidity': 60,
          'sampled_at': '1999999999',
        },
        'power': {'voltage': '220', 'energy': 12.5, 'sampled_at': 1999999998.0},
      });

      expect(dto.environment['temperature'], '28.5');
      expect(dto.power['voltage'], '220');
      expect(dto.power['energy'], 12.5);
      expect(dto.unixTime, 2000000000);
      expect(dto.environmentSampledAtEpochSeconds, 1999999999);
      expect(dto.powerSampledAtEpochSeconds, 1999999998);
    },
  );

  test('realtime DTO empty fallback maps to empty entity', () {
    final dto = mapRealtimeMonitoringDataToDto('invalid');
    final entity = mapRealtimeMonitoringDtoToEntity(dto);

    expect(entity.mcb1.energy, 0);
    expect(entity.sensorData.temperature, 0);
    expect(entity.heartbeatEpochSeconds, isNull);
  });

  test('malformed heartbeat and sampled_at map to null', () {
    final dto = mapRealtimeMonitoringDataToDto({
      'unix_time': 'invalid',
      'environment': {'sampled_at': -1},
      'power': {'sampled_at': 1.5},
    });

    expect(dto.unixTime, isNull);
    expect(dto.environmentSampledAtEpochSeconds, isNull);
    expect(dto.powerSampledAtEpochSeconds, isNull);
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

      expect(entity.temperature, 0);
      expect(entity.humidity, 0);
      expect(entity.connected, isFalse);
    },
  );
}
