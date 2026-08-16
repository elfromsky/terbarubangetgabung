import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty monitoring entities retain previous zero defaults', () {
    expect(SensorData.empty().temperature, 0);
    expect(SensorData.empty().humidity, 0);
    expect(SensorData.empty().connected, isFalse);
    expect(McbData.empty().voltage, 0);
    expect(McbDataCollection.empty().mcb1.energy, 0);
  });

  test('SensorData temperature categories use exact PRD boundaries', () {
    String category(double temperature) =>
        SensorData(temperature: temperature, humidity: 50).temperatureCategory;

    expect(category(25.7), 'Dingin');
    expect(category(25.7001), 'Sejuk');
    expect(category(28.6), 'Sejuk');
    expect(category(28.6001), 'Hangat');
    expect(category(31.4999), 'Hangat');
    expect(category(31.5), 'Panas');
  });

  test('SensorData humidity categories use exact PRD boundaries', () {
    String category(double humidity) =>
        SensorData(temperature: 28, humidity: humidity).humidityCategory;

    expect(category(60.25), 'Kering');
    expect(category(60.2501), 'Normal');
    expect(category(86.6199), 'Normal');
    expect(category(86.62), 'Lembap');
  });

  test('SensorData preserves heat index behavior', () {
    const belowThreshold = SensorData(temperature: 25, humidity: 60);
    const calculated = SensorData(temperature: 30, humidity: 70);

    expect(belowThreshold.heatIndex, 25);
    expect(calculated.heatIndex, closeTo(35.04, 0.01));
  });

  // Reference vectors from the NWS/WPC Rothfusz method (Fahrenheit regression,
  // converted back to Celsius). See docs/RESEARCH_PARAMETER_VALIDATION.md.
  // These are independent published values, not copies of the Dart formula.
  test('SensorData heat index matches NWS Rothfusz reference vectors', () {
    // (temperature °C, humidity %, expected heat index °C)
    const cases = <(double, double, double)>[
      (27, 40, 26.86),
      (27, 80, 29.74),
      (30, 50, 31.05),
      (30, 70, 35.04),
      (32, 60, 37.07),
      (35, 70, 50.34),
    ];

    for (final (temperature, humidity, expected) in cases) {
      final heatIndex =
          SensorData(temperature: temperature, humidity: humidity).heatIndex;
      expect(heatIndex, closeTo(expected, 0.02),
          reason: 'T=$temperature RH=$humidity');
    }
  });

  test('SensorData heat index uses temperature below 27 °C activation', () {
    expect(const SensorData(temperature: 26.9, humidity: 90).heatIndex, 26.9);
    expect(const SensorData(temperature: 27.0, humidity: 90).heatIndex,
        isNot(closeTo(27.0, 0.01)));
  });

  test('McbData copyWith and collection aggregates preserve values', () {
    const mcb = McbData(
      connected: true,
      voltage: 220,
      current: 1.5,
      power: 330,
      energy: 12.5,
      lastUpdate: 123,
    );
    final updated = mcb.copyWith(power: 400);
    final collection = McbDataCollection(mcb1: updated);

    expect(updated.power, 400);
    expect(updated.lastUpdate, 123);
    expect(collection.totalCurrent, 1.5);
    expect(collection.totalPower, 400);
    expect(collection.totalEnergy, 12.5);
  });

  test('DeviceAddress uses room and device keys for equality', () {
    const first = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
    const second = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
    const otherRoom = DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu');

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(otherRoom));
  });

  test('RoomDeviceValue distinguishes state-only and dimmable values', () {
    const stateOnly = RoomDeviceValue(isOn: true);
    const dimmable = RoomDeviceValue(isOn: true, brightness: 75);
    const dimmableOff = RoomDeviceValue(isOn: false, brightness: 0);

    expect(stateOnly.isDimmable, isFalse);
    expect(dimmable.isDimmable, isTrue);
    expect(dimmableOff.isDimmable, isTrue);
    expect(dimmableOff.brightness, 0);
    expect(stateOnly, isNot(dimmable));
  });

  test('RoomDeviceCollection lookup and set preserve immutable snapshots', () {
    const address = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
    const value = RoomDeviceValue(isOn: true);
    final empty = RoomDeviceCollection.empty();
    final updated = empty.set(address, value);

    expect(empty.find(address), isNull);
    expect(updated.find(address), value);
    expect(empty.values, isEmpty);
    expect(updated.values.length, 1);
    expect(updated.values[address], value);

    expect(
      () => updated.values[address] = const RoomDeviceValue(isOn: false),
      throwsUnsupportedError,
    );
  });

  test('missing device lookup remains unknown instead of off', () {
    const address = DeviceAddress(roomKey: 'teras', deviceKey: 'missing');
    expect(RoomDeviceCollection.empty().find(address), isNull);
  });
}
