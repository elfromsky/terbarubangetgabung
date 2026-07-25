import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

RoomDeviceCollection mapRoomDeviceCollectionDtoToEntity(
  RoomDeviceCollectionDto dto,
) {
  final rawRooms = dto.rawValue;
  if (rawRooms is! Map) return RoomDeviceCollection.empty();

  final values = <DeviceAddress, RoomDeviceValue>{};
  for (final roomEntry in rawRooms.entries) {
    final roomValue = roomEntry.value;
    if (roomValue is! Map) continue;

    final roomKey = roomEntry.key.toString();
    for (final deviceEntry in roomValue.entries) {
      final deviceValue = _mapDeviceValue(deviceEntry.value);
      if (deviceValue == null) continue;
      values[DeviceAddress(
            roomKey: roomKey,
            deviceKey: deviceEntry.key.toString(),
          )] =
          deviceValue;
    }
  }

  return RoomDeviceCollection(values: values);
}

RoomDeviceValue? _mapDeviceValue(Object? rawValue) {
  if (rawValue is bool) {
    return RoomDeviceValue(isOn: rawValue);
  }
  if (rawValue is! Map) return null;

  final state = rawValue['state'];
  if (state is! bool) return null;

  if (!rawValue.containsKey('brightness')) {
    if (rawValue.containsKey('lastUpdate') || rawValue.containsKey('source')) {
      return RoomDeviceValue(isOn: state);
    }
    return null;
  }

  final brightness = _parseBrightness(rawValue['brightness']);
  if (brightness == null) return null;

  return RoomDeviceValue(isOn: state, brightness: brightness);
}

int? _parseBrightness(Object? rawValue) {
  final numeric = rawValue is num
      ? rawValue
      : rawValue is String
      ? num.tryParse(rawValue)
      : null;
  if (numeric == null) return null;
  return numeric.toInt().clamp(0, 100).toInt();
}
