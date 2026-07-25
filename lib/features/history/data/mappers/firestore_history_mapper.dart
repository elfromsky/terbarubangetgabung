import 'package:esh/features/history/data/models/canonical_history_dto.dart';
import 'package:esh/features/history/data/models/legacy_history_dto.dart';

CanonicalHistoryDto mapFirestoreToCanonicalHistoryDto(
  Map<String, dynamic> data,
  String id,
) {
  final power = data['power'] as Map<String, dynamic>? ?? {};
  final environment = data['environment'] as Map<String, dynamic>? ?? {};
  return CanonicalHistoryDto(
    id: id,
    timestamp: data['timestamp'],
    power: power,
    environment: environment,
  );
}

LegacyHistoryDto mapFirestoreToLegacyHistoryDto(
  Map<String, dynamic> data,
  String id,
) {
  return LegacyHistoryDto(
    id: id,
    timestamp: data['timestamp'],
    mcb1: data['mcb1'],
    dht: data['dht'],
  );
}
