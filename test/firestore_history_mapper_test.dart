import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/mappers/firestore_history_mapper.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'canonical mapper retains sensorLogs schema and timestamp lastUpdate',
    () {
      final dto = mapFirestoreToCanonicalHistoryDto({
        'timestamp': Timestamp(1, 0),
        'power': {
          'connected': true,
          'voltage': 220,
          'current': '1.5',
          'power': 330,
          'energy': 4.25,
        },
        'environment': {'temperature': 27.5, 'humidity': '60'},
      }, 'canonical-1');
      final result = mapCanonicalHistoryDtoToEntity(dto);

      expect(result.id, 'canonical-1');
      expect(result.timestamp, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(result.mcb1!.lastUpdate, 1000);
      expect(result.mcb1!.lastUpdate, result.timestamp.millisecondsSinceEpoch);
      expect(result.sensorData!.humidity, 60);
    },
  );

  test(
    'canonical mapper throws for non-Map power for data-source record skip',
    () {
      expect(
        () => mapFirestoreToCanonicalHistoryDto({
          'timestamp': Timestamp(1, 0),
          'power': 'invalid',
          'environment': <String, dynamic>{},
        }, 'non-map-power'),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test('timestamp parser retains supported timestamp forms', () {
    expect(
      parseFirestoreTimestamp('13 Jul 2026 at 10:30:00 WIB'),
      DateTime(2026, 7, 13, 10, 30),
    );
    expect(
      parseFirestoreTimestamp(1500),
      DateTime.fromMillisecondsSinceEpoch(1500),
    );
  });

  test('timestamp parser bounds null and invalid fallbacks to now', () {
    final before = DateTime.now();
    final nullTimestamp = parseFirestoreTimestamp(null);
    final invalidTimestamp = parseFirestoreTimestamp('invalid');
    final after = DateTime.now();

    expect(nullTimestamp.compareTo(before) >= 0, isTrue);
    expect(nullTimestamp.compareTo(after) <= 0, isTrue);
    expect(invalidTimestamp.compareTo(before) >= 0, isTrue);
    expect(invalidTimestamp.compareTo(after) <= 0, isTrue);
  });

  test('legacy mapper retains nullable missing nodes', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': '2026-07-13T10:30:00.000',
    }, 'legacy-1');
    final result = mapLegacyHistoryDtoToEntity(dto);

    expect(result.mcb1, isNull);
    expect(result.sensorData, isNull);
  });

  test('legacy sort timestamp retains valid mapper timestamp', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': '2026-07-13T10:30:00.000',
      'mcb1': <String, dynamic>{},
      'dht': <String, dynamic>{},
    }, 'legacy-sort-valid');

    expect(legacyHistoryDtoSortTimestamp(dto), DateTime(2026, 7, 13, 10, 30));
  });

  test('legacy sort timestamp falls back for missing timestamp', () {
    final dto = mapFirestoreToLegacyHistoryDto(
      {},
      'legacy-sort-missing-timestamp',
    );
    final before = DateTime.now();
    final result = legacyHistoryDtoSortTimestamp(dto);
    final after = DateTime.now();

    expect(result.compareTo(before) >= 0, isTrue);
    expect(result.compareTo(after) <= 0, isTrue);
  });

  test('legacy sort timestamp falls back for invalid timestamp', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': 'invalid',
    }, 'legacy-sort-invalid-timestamp');
    final before = DateTime.now();
    final result = legacyHistoryDtoSortTimestamp(dto);
    final after = DateTime.now();

    expect(result.compareTo(before) >= 0, isTrue);
    expect(result.compareTo(after) <= 0, isTrue);
  });

  test('legacy sort timestamp falls back for malformed mcb1', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': '2026-07-13T10:30:00.000',
      'mcb1': 'invalid',
    }, 'legacy-sort-malformed-mcb1');
    final before = DateTime.now();
    final result = legacyHistoryDtoSortTimestamp(dto);
    final after = DateTime.now();

    expect(result.compareTo(before) >= 0, isTrue);
    expect(result.compareTo(after) <= 0, isTrue);
  });

  test('legacy sort timestamp falls back for malformed dht', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': '2026-07-13T10:30:00.000',
      'dht': 'invalid',
    }, 'legacy-sort-malformed-dht');
    final before = DateTime.now();
    final result = legacyHistoryDtoSortTimestamp(dto);
    final after = DateTime.now();

    expect(result.compareTo(before) >= 0, isTrue);
    expect(result.compareTo(after) <= 0, isTrue);
  });

  test('legacy mapper reads mcb1 and dht schema', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': '2026-07-13T10:30:00.000',
      'mcb1': {
        'connected': true,
        'voltage': 220,
        'current': 1.5,
        'power': 330,
        'energy': 2.5,
        'lastUpdate': 7,
      },
      'dht': {'temperature': 26, 'humidity': 55},
    }, 'legacy-2');
    final result = mapLegacyHistoryDtoToEntity(dto);

    expect(result.mcb1!.lastUpdate, 7);
    expect(result.sensorData!.temperature, 26);
  });

  test('legacy mapper retains sensor aliases', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': '2026-07-13T10:30:00.000',
      'dht': {'suhu': '26.5', 'kelembapan': 55, 'connected': true},
    }, 'legacy-aliases');
    final result = mapLegacyHistoryDtoToEntity(dto);

    expect(result.sensorData!.temperature, 26.5);
    expect(result.sensorData!.humidity, 55);
    expect(result.sensorData!.connected, isTrue);
  });

  test('legacy mapper retains malformed-record fallback', () {
    final dto = mapFirestoreToLegacyHistoryDto({
      'timestamp': 'invalid',
      'mcb1': {'connected': true},
    }, 'legacy-fallback');
    final result = mapLegacyHistoryDtoToEntity(dto);

    expect(result.id, 'legacy-fallback');
    expect(result.timestamp, isA<DateTime>());
    expect(result.mcb1, isNull);
    expect(result.sensorData, isNull);
  });

  test('legacy serializers retain Firestore and map payload differences', () {
    final historical = createLegacyHistoricalMcbData(
      McbDataCollection(
        mcb1: const McbData(
          connected: true,
          voltage: 220,
          current: 1.5,
          power: 330,
          energy: 2.5,
          lastUpdate: 7,
        ),
        sensorData: const SensorData(
          temperature: 26,
          humidity: 55,
          connected: true,
        ),
      ),
      'legacy-3',
      DateTime(2026, 7, 13, 10, 30),
    );

    final firestore = mapLegacyHistoricalEntityToDto(
      historical,
      timestampAsIsoString: false,
    ).toMap();
    final map = mapLegacyHistoricalEntityToDto(
      historical,
      timestampAsIsoString: true,
    ).toMap();

    expect(firestore['timestamp'], DateTime(2026, 7, 13, 10, 30));
    expect(map['timestamp'], '2026-07-13T10:30:00.000');
    expect(firestore['mcb1']['lastUpdate'], 7);
    expect(firestore['dht'], {'temperature': 26.0, 'humidity': 55.0});
  });
}
