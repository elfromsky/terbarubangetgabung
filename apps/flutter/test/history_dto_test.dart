import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/mappers/firestore_history_mapper.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical DTO retains raw timestamp and schema maps', () {
    final dto = mapFirestoreToCanonicalHistoryDto({
      'timestamp': Timestamp(1, 0),
      'power': {'energy': '4.25'},
      'environment': {'humidity': 60},
      'derived': {'estimatedCost': 1000},
    }, 'canonical');

    expect(dto.timestamp, Timestamp(1, 0));
    expect(dto.power['energy'], '4.25');
    expect(dto.environment['humidity'], 60);
    expect(dto.derived!['estimatedCost'], 1000);
  });

  test('canonical DTO entity mapper preserves timestamp lastUpdate', () {
    final dto = mapFirestoreToCanonicalHistoryDto({
      'timestamp': Timestamp(1, 0),
      'power': <String, dynamic>{},
      'environment': <String, dynamic>{},
    }, 'canonical');
    final entity = mapCanonicalHistoryDtoToEntity(dto);

    expect(entity.mcb1!.lastUpdate, 1000);
  });

  test('legacy DTO serializes native and ISO timestamps', () {
    final entity = HistoricalMcbData(
      id: 'legacy',
      timestamp: DateTime(2026, 7, 13, 10, 30),
      mcb1: const McbData(
        connected: true,
        voltage: 220,
        current: 1.5,
        power: 330,
        energy: 2.5,
        lastUpdate: 7,
      ),
      sensorData: const SensorData(temperature: 26, humidity: 55),
    );

    final firestore = mapLegacyHistoricalEntityToDto(
      entity,
      timestampAsIsoString: false,
    ).toMap();
    final map = mapLegacyHistoricalEntityToDto(
      entity,
      timestampAsIsoString: true,
    ).toMap();

    expect(firestore['timestamp'], entity.timestamp);
    expect(map['timestamp'], entity.timestamp.toIso8601String());
    expect(firestore['dht'], {'temperature': 26.0, 'humidity': 55.0});
  });
}
