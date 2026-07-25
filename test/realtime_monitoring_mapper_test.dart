import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical telemetry maps numeric and nested Firebase values', () {
    final dto = mapRealtimeMonitoringDataToDto({
      'environment': {'temperature': '28.5', 'humidity': 60, 'connected': true},
      'power': {
        'connected': true,
        'voltage': 220,
        'current': '1.25',
        'power': 275.5,
        'energy': '12.75',
      },
    });
    final result = mapRealtimeMonitoringDtoToEntity(dto);

    expect(result.sensorData.temperature, 28.5);
    expect(result.mcb1.current, 1.25);
    expect(result.mcb1.lastUpdate, 0);
  });

  test('canonical telemetry malformed root stays empty', () {
    final dto = mapRealtimeMonitoringDataToDto('invalid');
    final result = mapRealtimeMonitoringDtoToEntity(dto);

    expect(result.mcb1.energy, 0);
    expect(result.sensorData.connected, isFalse);
  });

  test('legacy sensor mapper accepts aliases', () {
    final dto = mapRealtimeSensorDataToDto({
      'suhu': '26.5',
      'kelembapan': 70,
      'connected': true,
    });
    final result = mapSensorDataDtoToEntity(dto);

    expect(result.temperature, 26.5);
    expect(result.humidity, 70);
    expect(result.connected, isTrue);
  });

  test('legacy sensor mapper accepts temp and hum aliases', () {
    final dto = mapRealtimeSensorDataToDto({
      'temp': '26.5',
      'hum': 70,
      'connected': true,
    });
    final result = mapSensorDataDtoToEntity(dto);

    expect(result.temperature, 26.5);
    expect(result.humidity, 70);
    expect(result.connected, isTrue);
  });

  test('legacy sensor mapper falls back for invalid numeric strings', () {
    final dto = mapRealtimeSensorDataToDto({
      'temp': 'invalid',
      'hum': 'not-a-number',
    });
    final result = mapSensorDataDtoToEntity(dto);

    expect(result.temperature, 0);
    expect(result.humidity, 0);
  });

  test('legacy sensor mapper returns empty data for invalid value', () {
    final dto = mapRealtimeSensorDataToDto('invalid');
    final result = mapSensorDataDtoToEntity(dto);

    expect(result.temperature, 0);
    expect(result.humidity, 0);
  });
}
