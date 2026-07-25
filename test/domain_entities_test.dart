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

  test('SensorData retains heat index and comfort rules', () {
    const comfortable = SensorData(temperature: 25, humidity: 60);
    const hot = SensorData(temperature: 31, humidity: 60);

    expect(comfortable.heatIndex, 25);
    expect(comfortable.comfortLevel, 'Nyaman');
    expect(hot.comfortLevel, 'Panas');
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
