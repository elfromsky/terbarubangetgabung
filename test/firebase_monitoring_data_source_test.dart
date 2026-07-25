import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'monitoring DTO/entity mapper returns empty data for malformed root',
    () {
      final dto = mapRealtimeMonitoringDataToDto('invalid');
      final result = mapRealtimeMonitoringDtoToEntity(dto);

      expect(result.mcb1.connected, isFalse);
      expect(result.mcb1.voltage, 0);
      expect(result.sensorData.temperature, 0);
    },
  );

  test('monitoring DTO/entity mapper normalizes numeric Firebase values', () {
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
    expect(result.sensorData.humidity, 60);
    expect(result.sensorData.connected, isTrue);
    expect(result.mcb1.connected, isTrue);
    expect(result.mcb1.voltage, 220);
    expect(result.mcb1.current, 1.25);
    expect(result.mcb1.power, 275.5);
    expect(result.mcb1.energy, 12.75);
  });

  test(
    'monitoring DTO/entity mapper defaults null numeric telemetry values to zero',
    () {
      final dto = mapRealtimeMonitoringDataToDto({
        'environment': {'temperature': null, 'humidity': null},
        'power': {
          'voltage': null,
          'current': null,
          'power': null,
          'energy': null,
        },
      });
      final result = mapRealtimeMonitoringDtoToEntity(dto);

      expect(result.sensorData.temperature, 0);
      expect(result.sensorData.humidity, 0);
      expect(result.mcb1.voltage, 0);
      expect(result.mcb1.current, 0);
      expect(result.mcb1.power, 0);
      expect(result.mcb1.energy, 0);
    },
  );
}
