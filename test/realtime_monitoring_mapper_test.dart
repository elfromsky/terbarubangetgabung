import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical telemetry maps numeric and nested Firebase values', () {
    final dto = mapRealtimeMonitoringDataToDto({
      'unix_time': '2000000000',
      'environment': {
        'temperature': '28.5',
        'humidity': 60,
        'connected': true,
        'sampled_at': 1999999999.0,
      },
      'power': {
        'connected': true,
        'voltage': 220,
        'current': '1.25',
        'power': 275.5,
        'energy': '12.75',
        'sampled_at': '1999999998',
      },
    });
    final result = mapRealtimeMonitoringDtoToEntity(dto);

    expect(result.sensorData.temperature, 28.5);
    expect(result.sensorData.connected, isTrue);
    expect(result.sensorData.sampledAtEpochSeconds, 1999999999);
    expect(result.mcb1.current, 1.25);
    expect(result.mcb1.connected, isTrue);
    expect(result.mcb1.sampledAtEpochSeconds, 1999999998);
    expect(result.heartbeatEpochSeconds, 2000000000);
    expect(result.mcb1.lastUpdate, 0);
  });

  test('canonical telemetry malformed root stays empty', () {
    final dto = mapRealtimeMonitoringDataToDto('invalid');
    final result = mapRealtimeMonitoringDtoToEntity(dto);

    expect(result.mcb1.energy, 0);
    expect(result.sensorData.connected, isFalse);
  });

  test('disconnected environment maps backend sentinel values to zero', () {
    final dto = mapRealtimeMonitoringDataToDto({
      'environment': {'temperature': -1, 'humidity': -1, 'connected': false},
      'power': {},
    });
    final result = mapRealtimeMonitoringDtoToEntity(dto);

    expect(result.sensorData.temperature, 0);
    expect(result.sensorData.humidity, 0);
    expect(result.sensorData.connected, isFalse);
  });

  test('missing sampled_at makes otherwise valid modules unavailable', () {
    final result = mapRealtimeMonitoringDtoToEntity(
      mapRealtimeMonitoringDataToDto({
        'environment': {'temperature': 28, 'humidity': 60, 'connected': true},
        'power': {
          'voltage': 220,
          'current': 1,
          'power': 220,
          'energy': 1,
          'connected': true,
        },
      }),
    );

    expect(result.sensorData.connected, isFalse);
    expect(result.mcb1.connected, isFalse);
  });

  test('malformed and out-of-range values make modules unavailable', () {
    final result = mapRealtimeMonitoringDtoToEntity(
      mapRealtimeMonitoringDataToDto({
        'environment': {
          'temperature': 'NaN',
          'humidity': 101,
          'connected': true,
          'sampled_at': 2000000000,
        },
        'power': {
          'voltage': 79.99,
          'current': 101,
          'power': 23000.01,
          'energy': 10000,
          'connected': true,
          'sampled_at': 2000000000,
        },
      }),
    );

    expect(result.sensorData.connected, isFalse);
    expect(result.mcb1.connected, isFalse);
  });

  test('telemetry range boundaries are inclusive', () {
    for (final values in [
      {
        'environment': {'temperature': -40, 'humidity': 0},
        'power': {'voltage': 80, 'current': 0, 'power': 0, 'energy': 0},
      },
      {
        'environment': {'temperature': 125, 'humidity': 100},
        'power': {
          'voltage': 260,
          'current': 100,
          'power': 23000,
          'energy': 9999.99,
        },
      },
    ]) {
      final environment = values['environment']!;
      final power = values['power']!;
      final result = mapRealtimeMonitoringDtoToEntity(
        mapRealtimeMonitoringDataToDto({
          'environment': {
            ...environment,
            'connected': true,
            'sampled_at': 2000000000,
          },
          'power': {...power, 'connected': true, 'sampled_at': 2000000000},
        }),
      );

      expect(result.sensorData.connected, isTrue);
      expect(result.mcb1.connected, isTrue);
    }
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
