import 'package:esh/features/monitoring/data/mappers/room_device_mapper.dart';
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('null and non-map roots produce empty collection', () {
    expect(
      mapRoomDeviceCollectionDtoToEntity(
        const RoomDeviceCollectionDto(rawValue: null),
      ).values,
      isEmpty,
    );
    expect(
      mapRoomDeviceCollectionDtoToEntity(
        const RoomDeviceCollectionDto(rawValue: 'invalid'),
      ).values,
      isEmpty,
    );
  });

  test('legacy flat room nodes are ignored', () {
    final result = mapRoomDeviceCollectionDtoToEntity(
      const RoomDeviceCollectionDto(
        rawValue: {
          'teras': {'lampu': true, 'sanyo': false},
        },
      ),
    );

    expect(result.values, isEmpty);
  });

  test('state-only object nodes map without brightness', () {
    final result = mapRoomDeviceCollectionDtoToEntity(
      const RoomDeviceCollectionDto(
        rawValue: {
          'lorong': {
            'source': 'slave',
            'tools': {
              'blower': {'state': true, 'lastUpdate': 123},
            },
          },
        },
      ),
    );

    expect(
      result.find(const DeviceAddress(roomKey: 'lorong', deviceKey: 'blower')),
      const RoomDeviceValue(isOn: true),
    );
  });

  test('dimmable nodes preserve brightness including zero when off', () {
    final result = mapRoomDeviceCollectionDtoToEntity(
      const RoomDeviceCollectionDto(
        rawValue: {
          'kamar_1': {
            'source': 'slave',
            'tools': {
              'lampu': {'state': false, 'brightness': 0},
            },
          },
        },
      ),
    );

    expect(
      result.find(const DeviceAddress(roomKey: 'kamar_1', deviceKey: 'lampu')),
      const RoomDeviceValue(isOn: false, brightness: 0),
    );
  });

  test(
    'integer double and string brightness values become clamped integers',
    () {
      final result = mapRoomDeviceCollectionDtoToEntity(
        const RoomDeviceCollectionDto(
          rawValue: {
            'dapur': {
              'source': 'slave',
              'tools': {
                'int': {'state': true, 'brightness': 40},
                'double': {'state': true, 'brightness': 50.9},
                'string': {'state': true, 'brightness': '75'},
                'high': {'state': true, 'brightness': 125},
                'low': {'state': false, 'brightness': -5},
              },
            },
          },
        ),
      );

      expect(
        result
            .find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'int'))
            ?.brightness,
        40,
      );
      expect(
        result
            .find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'double'))
            ?.brightness,
        50,
      );
      expect(
        result
            .find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'string'))
            ?.brightness,
        75,
      );
      expect(
        result
            .find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'high'))
            ?.brightness,
        100,
      );
      expect(
        result
            .find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'low'))
            ?.brightness,
        0,
      );
    },
  );

  test(
    'malformed rooms and device nodes are ignored without inventing off',
    () {
      final result = mapRoomDeviceCollectionDtoToEntity(
        const RoomDeviceCollectionDto(
          rawValue: {
            'invalidRoom': 'invalid',
            'dapur': {
              'source': 'slave',
              'tools': {
                'stateOnly': {'state': true},
                'invalidState': {'state': 'true', 'brightness': 50},
                'invalidBrightness': {'state': true, 'brightness': 'none'},
                'legacyBool': true,
              },
            },
          },
        ),
      );

      expect(
        result.find(
          const DeviceAddress(roomKey: 'invalidRoom', deviceKey: 'invalid'),
        ),
        isNull,
      );
      expect(
        result.find(
          const DeviceAddress(roomKey: 'dapur', deviceKey: 'stateOnly'),
        ),
        const RoomDeviceValue(isOn: true),
      );
      expect(
        result.find(
          const DeviceAddress(roomKey: 'dapur', deviceKey: 'invalidState'),
        ),
        isNull,
      );
      expect(
        result.find(
          const DeviceAddress(roomKey: 'dapur', deviceKey: 'invalidBrightness'),
        ),
        isNull,
      );
      expect(
        result.find(
          const DeviceAddress(roomKey: 'dapur', deviceKey: 'legacyBool'),
        ),
        isNull,
      );
    },
  );
}
