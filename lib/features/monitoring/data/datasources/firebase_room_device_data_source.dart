import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:firebase_database/firebase_database.dart';

abstract interface class RoomDeviceDataSource {
  Stream<RoomDeviceCollectionDto> getRoomDevicesStream();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}

String roomDeviceCommandPath(String roomKey, String deviceKey) {
  return 'commands/rooms/$roomKey/$deviceKey';
}

Map<String, Object> roomDeviceCommandPayload({
  required String requestId,
  required Object createdAt,
  required bool isOn,
  required int brightness,
  required bool supportsBrightness,
}) {
  return {
    'protocolVersion': 1,
    'requestId': requestId,
    'createdAt': createdAt,
    'state': isOn,
    if (supportsBrightness) 'brightness': brightness,
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
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {
    try {
      final commandReference = database.child(
        roomDeviceCommandPath(roomKey, deviceKey),
      );
      await commandReference.set(
        roomDeviceCommandPayload(
          requestId:
              commandReference.push().key ??
              '${DateTime.now().microsecondsSinceEpoch}',
          createdAt: ServerValue.timestamp,
          isOn: isOn,
          brightness: brightness,
          supportsBrightness: supportsBrightness,
        ),
      );
    } catch (error) {
      throw Exception('Failed to control device: $error');
    }
  }
}
