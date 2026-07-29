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

  test('room device command uses canonical path and simple payload', () {
    expect(
      roomDeviceCommandPath('dapur', 'lampu'),
      'commands/rooms/dapur/tools/lampu',
    );
    expect(
      roomDeviceCommandPayload(
        isOn: true,
        brightness: 75,
        supportsBrightness: true,
      ),
      {'state': true, 'brightness': 75},
    );
  });

  test('state-only command contains only state', () {
    expect(
      roomDeviceCommandPayload(
        isOn: false,
        brightness: 0,
        supportsBrightness: false,
      ),
      {'state': false},
    );
  });

  test('dimmer payload clamps and normalizes on zero to one', () {
    expect(
      roomDeviceCommandPayload(
        isOn: true,
        brightness: 0,
        supportsBrightness: true,
      ),
      {'state': true, 'brightness': 1},
    );
    expect(
      roomDeviceCommandPayload(
        isOn: true,
        brightness: 150,
        supportsBrightness: true,
      ),
      {'state': true, 'brightness': 100},
    );
  });

  test('off dimmer retains supplied clamped brightness', () {
    expect(
      roomDeviceCommandPayload(
        isOn: false,
        brightness: 35,
        supportsBrightness: true,
      ),
      {'state': false, 'brightness': 35},
    );
  });

  test('bulk updates target both canonical command leaves', () {
    expect(
      roomDeviceCommandUpdates(const [
        RoomDeviceCommandDto(
          roomKey: 'kamar_1',
          deviceKey: 'lampu',
          isOn: true,
          brightness: 60,
          supportsBrightness: true,
        ),
        RoomDeviceCommandDto(
          roomKey: 'kamar_2',
          deviceKey: 'lampu',
          isOn: false,
          brightness: 60,
          supportsBrightness: true,
        ),
      ]),
      {
        'commands/rooms/kamar_1/tools/lampu': {'state': true, 'brightness': 60},
        'commands/rooms/kamar_2/tools/lampu': {
          'state': false,
          'brightness': 60,
        },
      },
    );
  });
}
