import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/mappers/firestore_history_mapper.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:esh/features/history/data/models/canonical_history_dto.dart';
import 'package:esh/features/history/data/models/legacy_history_dto.dart';
import 'package:flutter/widgets.dart';

const canonicalHistoryCollection = 'sensorLogs';
const legacyHistoryCollection = 'energyData';

abstract interface class HistoryDataSource {
  Future<List<CanonicalHistoryDto>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });

  Future<void> saveSensorLog(Map<String, dynamic> data);
}

class FirebaseHistoryDataSource implements HistoryDataSource {
  final FirebaseFirestore firestore;

  FirebaseHistoryDataSource({required this.firestore});

  @override
  Future<void> saveSensorLog(Map<String, dynamic> data) async {
    try {
      await firestore.collection(canonicalHistoryCollection).add(data);
    } catch (error) {
      throw Exception('Failed to save sensor log: $error');
    }
  }

  @override
  Future<List<CanonicalHistoryDto>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    try {
      final query = firestore
          .collection(canonicalHistoryCollection)
          .where('timestamp', isGreaterThanOrEqualTo: startDate)
          .where('timestamp', isLessThan: endDate)
          .orderBy('timestamp', descending: false)
          .limit(limit);
      final querySnapshot = await query.get();
      final historyData = <CanonicalHistoryDto>[];

      for (final doc in querySnapshot.docs) {
        try {
          historyData.add(
            mapFirestoreToCanonicalHistoryDto(doc.data(), doc.id),
          );
        } catch (error) {
          debugPrint('Error parsing doc ${doc.id}: $error');
        }
      }
      return historyData;
    } catch (error) {
      throw Exception('Failed to fetch historical data: $error');
    }
  }

  Future<List<CanonicalHistoryDto>> getTodayHistoryData() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return getHistoricalData(
      startDate: startOfDay,
      endDate: startOfDay.add(const Duration(days: 1)),
      limit: 288,
    );
  }

  Future<List<CanonicalHistoryDto>> getWeekHistoryData() async {
    final endDate = DateTime.now();
    return getHistoricalData(
      startDate: endDate.subtract(const Duration(days: 7)),
      endDate: endDate,
      limit: 500,
    );
  }

  Future<List<CanonicalHistoryDto>> getMonthHistoryData() async {
    final endDate = DateTime.now();
    return getHistoricalData(
      startDate: DateTime(endDate.year, endDate.month - 1, endDate.day),
      endDate: endDate,
      limit: 1000,
    );
  }

  Future<List<LegacyHistoryDto>> getAllHistoryData() async {
    try {
      final querySnapshot = await firestore
          .collection(legacyHistoryCollection)
          .orderBy('timestamp', descending: false)
          .get();
      final historyData = <LegacyHistoryDto>[];
      for (final doc in querySnapshot.docs) {
        try {
          historyData.add(mapFirestoreToLegacyHistoryDto(doc.data(), doc.id));
        } catch (_) {}
      }
      return historyData;
    } catch (error) {
      throw Exception('Failed to fetch all historical data: $error');
    }
  }

  Future<List<LegacyHistoryDto>> getHistoricalDataSafe({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 100,
  }) async {
    try {
      final snapshot = await firestore
          .collection(legacyHistoryCollection)
          .where('timestamp', isGreaterThanOrEqualTo: startDate)
          .where('timestamp', isLessThanOrEqualTo: endDate)
          .orderBy('timestamp', descending: false)
          .limit(limit)
          .get();
      final result = <LegacyHistoryDto>[];
      for (final doc in snapshot.docs) {
        try {
          result.add(mapFirestoreToLegacyHistoryDto(doc.data(), doc.id));
        } catch (_) {}
      }
      return _sortLegacyHistoryData(result);
    } catch (_) {
      return [];
    }
  }

  Future<List<LegacyHistoryDto>> getAllHistoryDataSafe() async {
    try {
      final snapshot = await firestore
          .collection(legacyHistoryCollection)
          .orderBy('timestamp', descending: false)
          .limit(500)
          .get();
      final result = <LegacyHistoryDto>[];
      for (final doc in snapshot.docs) {
        try {
          result.add(mapFirestoreToLegacyHistoryDto(doc.data(), doc.id));
        } catch (_) {}
      }
      return _sortLegacyHistoryData(result);
    } catch (_) {
      return [];
    }
  }

  Future<void> debugFirestoreData() async {
    try {
      final snapshot = await firestore
          .collection(legacyHistoryCollection)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) {
        throw Exception('No documents found in energyData collection');
      }
      snapshot.docs.first.data().forEach((key, value) {});
    } catch (error) {
      throw Exception('Failed to debug Firestore data: $error');
    }
  }

  Future<void> saveHistoricalData(LegacyHistoryDto data) async {
    try {
      await firestore
          .collection(legacyHistoryCollection)
          .doc(data.id)
          .set(data.toMap());
    } catch (error) {
      throw Exception('Failed to save historical data: $error');
    }
  }

  List<LegacyHistoryDto> _sortLegacyHistoryData(List<LegacyHistoryDto> data) {
    final timestampedData = data
        .map(
          (dto) => _LegacyHistorySortEntry(
            data: dto,
            timestamp: legacyHistoryDtoSortTimestamp(dto),
          ),
        )
        .toList();
    timestampedData.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return timestampedData.map((entry) => entry.data).toList();
  }
}

class _LegacyHistorySortEntry {
  final LegacyHistoryDto data;
  final DateTime timestamp;

  const _LegacyHistorySortEntry({required this.data, required this.timestamp});
}
