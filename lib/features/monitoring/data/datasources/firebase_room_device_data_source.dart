import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:firebase_database/firebase_database.dart';

abstract interface class RoomDeviceDataSource {
  Stream<RoomDeviceCollectionDto> getRoomDevicesStream();
  Future<void> controlRoomDevices(List<RoomDeviceCommandDto> commands);
}

class RoomDeviceCommandDto {
  final String roomKey;
  final String deviceKey;
  final bool isOn;
  final int brightness;
  final bool supportsBrightness;

  const RoomDeviceCommandDto({
    required this.roomKey,
    required this.deviceKey,
    required this.isOn,
    required this.brightness,
    required this.supportsBrightness,
  });
}

String roomDeviceCommandPath(String roomKey, String deviceKey) {
  return 'commands/rooms/$roomKey/tools/$deviceKey';
}

Map<String, Object> roomDeviceCommandPayload({
  required bool isOn,
  required int brightness,
  required bool supportsBrightness,
}) {
  var normalizedBrightness = brightness.clamp(0, 100).toInt();
  if (supportsBrightness && isOn && normalizedBrightness == 0) {
    normalizedBrightness = 1;
  }

  return {
    'state': isOn,
    if (supportsBrightness) 'brightness': normalizedBrightness,
  };
}

Map<String, Object> roomDeviceCommandUpdates(
  Iterable<RoomDeviceCommandDto> commands,
) {
  return {
    for (final command in commands)
      roomDeviceCommandPath(
        command.roomKey,
        command.deviceKey,
      ): roomDeviceCommandPayload(
        isOn: command.isOn,
        brightness: command.brightness,
        supportsBrightness: command.supportsBrightness,
      ),
  };
}

class FirebaseRoomDeviceDataSource implements RoomDeviceDataSource {
  final DatabaseReference database;

  FirebaseRoomDeviceDataSource({required this.database});

  @override
  Stream<RoomDeviceCollectionDto> getRoomDevicesStream() {
    return database
        .child('rooms')
        .onValue
        .map(
          (event) => RoomDeviceCollectionDto(rawValue: event.snapshot.value),
        );
  }

  @override
  Future<void> controlRoomDevices(List<RoomDeviceCommandDto> commands) async {
    try {
      await database.update(roomDeviceCommandUpdates(commands));
    } catch (error) {
      throw Exception('Failed to control device: $error');
    }
  }
}
