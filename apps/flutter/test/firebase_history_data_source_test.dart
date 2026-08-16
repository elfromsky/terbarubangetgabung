import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/mappers/firestore_history_mapper.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history collection constants retain canonical and legacy names', () {
    expect(canonicalHistoryCollection, 'sensorLogs');
    expect(legacyHistoryCollection, 'energyData');
  });

  test('parseFirestoreTimestamp accepts Timestamp and ISO string', () {
    expect(
      parseFirestoreTimestamp(Timestamp(1, 500000000)),
      DateTime.fromMillisecondsSinceEpoch(1500),
    );
    expect(
      parseFirestoreTimestamp('2026-07-13T10:30:00.000'),
      DateTime(2026, 7, 13, 10, 30),
    );
  });

  test('canonical DTO/entity mapper maps sensorLogs record', () {
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
    }, 'record-1');
    final result = mapCanonicalHistoryDtoToEntity(dto);

    expect(result.id, 'record-1');
    expect(result.timestamp, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(result.mcb1!.connected, isTrue);
    expect(result.mcb1!.current, 1.5);
    expect(result.sensorData!.temperature, 27.5);
    expect(result.sensorData!.humidity, 60);
  });
}
