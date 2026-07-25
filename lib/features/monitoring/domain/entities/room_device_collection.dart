import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

class RoomDeviceCollection {
  final Map<DeviceAddress, RoomDeviceValue> values;

  RoomDeviceCollection({required Map<DeviceAddress, RoomDeviceValue> values})
    : values = Map<DeviceAddress, RoomDeviceValue>.unmodifiable(values);

  factory RoomDeviceCollection.empty() {
    return RoomDeviceCollection(values: const {});
  }

  RoomDeviceValue? find(DeviceAddress address) {
    return values[address];
  }

  RoomDeviceCollection set(DeviceAddress address, RoomDeviceValue value) {
    final next = Map<DeviceAddress, RoomDeviceValue>.from(values)
      ..[address] = value;
    return RoomDeviceCollection(values: next);
  }
}
