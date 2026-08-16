import 'dart:convert';
import 'dart:math';

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

final Random _secureRandom = Random.secure();

String generateRoomDeviceRequestId() {
  final bytes = List<int>.generate(
    16,
    (_) => _secureRandom.nextInt(256),
    growable: false,
  );
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Map<String, Object> roomDeviceCommandPayload({
  required bool isOn,
  required int brightness,
  required bool supportsBrightness,
  required String requestId,
  required int issuedAtEpochMs,
}) {
  if (requestId.isEmpty || requestId.length > 31) {
    throw ArgumentError.value(
      requestId,
      'requestId',
      'Must contain 1..31 characters',
    );
  }

  var normalizedBrightness = brightness.clamp(0, 100).toInt();
  if (supportsBrightness && isOn && normalizedBrightness == 0) {
    normalizedBrightness = 1;
  }

  return {
    'state': isOn,
    if (supportsBrightness) 'brightness': normalizedBrightness,
    'request_id': requestId,
    'issued_at': issuedAtEpochMs,
  };
}

Map<String, Object> roomDeviceCommandUpdates(
  Iterable<RoomDeviceCommandDto> commands, {
  required String Function() requestIdFactory,
  required int issuedAtEpochMs,
}) {
  final updates = <String, Object>{};
  final requestIds = <String>{};

  for (final command in commands) {
    final requestId = requestIdFactory();
    if (!requestIds.add(requestId)) {
      throw StateError('Duplicate request ID in command update: $requestId');
    }
    updates[roomDeviceCommandPath(
      command.roomKey,
      command.deviceKey,
    )] = roomDeviceCommandPayload(
      isOn: command.isOn,
      brightness: command.brightness,
      supportsBrightness: command.supportsBrightness,
      requestId: requestId,
      issuedAtEpochMs: issuedAtEpochMs,
    );
  }

  return updates;
}

class FirebaseRoomDeviceDataSource implements RoomDeviceDataSource {
  final DatabaseReference database;
  final String Function() requestIdFactory;
  final DateTime Function() now;

  FirebaseRoomDeviceDataSource({
    required this.database,
    this.requestIdFactory = generateRoomDeviceRequestId,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

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
      final offsetSnapshot = await database
          .child('.info/serverTimeOffset')
          .get();
      final offsetValue = offsetSnapshot.value;
      if (offsetValue is! num) {
        throw StateError('Firebase server time offset is unavailable');
      }
      final issuedAtEpochMs =
          now().millisecondsSinceEpoch + offsetValue.round();
      await database.update(
        roomDeviceCommandUpdates(
          commands,
          requestIdFactory: requestIdFactory,
          issuedAtEpochMs: issuedAtEpochMs,
        ),
      );
    } catch (error) {
      throw Exception('Failed to control device: $error');
    }
  }
}
