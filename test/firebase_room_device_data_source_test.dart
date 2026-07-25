import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('room device DTO retains raw /rooms snapshot for data mapper', () {
    const rawValue = {
      'teras': {'lampu': true},
    };
    const dto = RoomDeviceCollectionDto(rawValue: rawValue);

    expect(dto.rawValue, rawValue);
  });

  test(
    'room device DTO accepts malformed snapshot without defaulting state',
    () {
      const dto = RoomDeviceCollectionDto(rawValue: 'invalid');
      expect(dto.rawValue, 'invalid');
    },
  );

  test('room device command uses canonical path and dimmable payload', () {
    expect(
      roomDeviceCommandPath('dapur', 'lampu'),
      'commands/rooms/dapur/lampu',
    );
    expect(
      roomDeviceCommandPayload(
        requestId: 'request-1',
        createdAt: 123,
        isOn: true,
        brightness: 75,
        supportsBrightness: true,
      ),
      {
        'protocolVersion': 1,
        'requestId': 'request-1',
        'createdAt': 123,
        'state': true,
        'brightness': 75,
      },
    );
  });

  test('state-only command uses envelope without brightness', () {
    expect(
      roomDeviceCommandPayload(
        requestId: 'request-2',
        createdAt: 456,
        isOn: false,
        brightness: 0,
        supportsBrightness: false,
      ),
      {
        'protocolVersion': 1,
        'requestId': 'request-2',
        'createdAt': 456,
        'state': false,
      },
    );
  });
}
