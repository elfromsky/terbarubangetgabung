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

  const issuedAtEpochMs = 1786665600000;

  test('room device command uses canonical path and exact dimmer payload', () {
    expect(
      roomDeviceCommandPath('dapur', 'lampu'),
      'commands/rooms/dapur/tools/lampu',
    );
    expect(
      roomDeviceCommandPayload(
        isOn: true,
        brightness: 75,
        supportsBrightness: true,
        requestId: 'request-1',
        issuedAtEpochMs: issuedAtEpochMs,
      ),
      {
        'state': true,
        'brightness': 75,
        'request_id': 'request-1',
        'issued_at': issuedAtEpochMs,
      },
    );
  });

  test('relay command contains state and freshness metadata only', () {
    expect(
      roomDeviceCommandPayload(
        isOn: false,
        brightness: 0,
        supportsBrightness: false,
        requestId: 'request-2',
        issuedAtEpochMs: issuedAtEpochMs,
      ),
      {'state': false, 'request_id': 'request-2', 'issued_at': issuedAtEpochMs},
    );
  });

  test('dimmer payload clamps and normalizes on zero to one', () {
    expect(
      roomDeviceCommandPayload(
        isOn: true,
        brightness: 0,
        supportsBrightness: true,
        requestId: 'request-3',
        issuedAtEpochMs: issuedAtEpochMs,
      ),
      {
        'state': true,
        'brightness': 1,
        'request_id': 'request-3',
        'issued_at': issuedAtEpochMs,
      },
    );
    expect(
      roomDeviceCommandPayload(
        isOn: true,
        brightness: 150,
        supportsBrightness: true,
        requestId: 'request-4',
        issuedAtEpochMs: issuedAtEpochMs,
      ),
      {
        'state': true,
        'brightness': 100,
        'request_id': 'request-4',
        'issued_at': issuedAtEpochMs,
      },
    );
  });

  test('off dimmer retains supplied clamped brightness', () {
    expect(
      roomDeviceCommandPayload(
        isOn: false,
        brightness: 35,
        supportsBrightness: true,
        requestId: 'request-5',
        issuedAtEpochMs: issuedAtEpochMs,
      ),
      {
        'state': false,
        'brightness': 35,
        'request_id': 'request-5',
        'issued_at': issuedAtEpochMs,
      },
    );
  });

  test('generated request IDs are unique URL-safe 128-bit values', () {
    final ids = List.generate(100, (_) => generateRoomDeviceRequestId());

    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, hasLength(22));
      expect(id.length, lessThanOrEqualTo(31));
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    }
  });

  test('request IDs must be nonempty and at most 31 characters', () {
    final maxLengthId = List.filled(31, 'x').join();
    final tooLongId = '${maxLengthId}x';
    Map<String, Object> build(String requestId) => roomDeviceCommandPayload(
      isOn: false,
      brightness: 0,
      supportsBrightness: false,
      requestId: requestId,
      issuedAtEpochMs: issuedAtEpochMs,
    );

    expect(() => build(''), throwsArgumentError);
    expect(() => build(tooLongId), throwsArgumentError);
    expect(build(maxLengthId)['request_id'], maxLengthId);
  });

  test('bulk updates give paired command leaves distinct request IDs', () {
    var requestNumber = 0;

    expect(
      roomDeviceCommandUpdates(
        const [
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
        ],
        requestIdFactory: () => 'request-${++requestNumber}',
        issuedAtEpochMs: issuedAtEpochMs,
      ),
      {
        'commands/rooms/kamar_1/tools/lampu': {
          'state': true,
          'brightness': 60,
          'request_id': 'request-1',
          'issued_at': issuedAtEpochMs,
        },
        'commands/rooms/kamar_2/tools/lampu': {
          'state': false,
          'brightness': 60,
          'request_id': 'request-2',
          'issued_at': issuedAtEpochMs,
        },
      },
    );
  });

  test('bulk update rejects duplicate request IDs', () {
    const commands = [
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
    ];

    expect(
      () => roomDeviceCommandUpdates(
        commands,
        requestIdFactory: () => 'same-request',
        issuedAtEpochMs: issuedAtEpochMs,
      ),
      throwsStateError,
    );
  });
}
