import 'dart:async';
import 'package:esh/models/model.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

abstract class MonitoringRepository {
  Stream<McbDataCollection> getMonitoringDataStream();
  Stream<Map<String, dynamic>> getRoomDevicesStream();
  Stream<bool> getConnectionStatus();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}

abstract class HistoryRepository {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}

class FirebaseService implements MonitoringRepository, HistoryRepository {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  @override
  Stream<McbDataCollection> getMonitoringDataStream() {
    return _database.child('device/sensorData').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return McbDataCollection.empty();

      final sensorRoot = _convertToMapStringDynamic(value);
      final environment = sensorRoot['environment'];
      final power = sensorRoot['power'];
      final environmentMap = environment is Map
          ? _convertToMapStringDynamic(environment)
          : <String, dynamic>{};
      final powerMap = power is Map
          ? _convertToMapStringDynamic(power)
          : <String, dynamic>{};

      final sensorData = SensorData(
        temperature: _parseDouble(environmentMap['temperature']),
        humidity: _parseDouble(environmentMap['humidity']),
        connected: environmentMap['connected'] == true,
      );
      final mcbData = McbData(
        connected: powerMap['connected'] == true,
        voltage: _parseDouble(powerMap['voltage']),
        current: _parseDouble(powerMap['current']),
        power: _parseDouble(powerMap['power']),
        energy: _parseDouble(powerMap['energy']),
      );

      return McbDataCollection(mcb1: mcbData, sensorData: sensorData);
    });
  }

  Stream<Map<String, dynamic>> getRawDatabaseStream() {
    return _database.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return {};
      return _convertToMapStringDynamic(data);
    });
  }

  @override
  Stream<Map<String, dynamic>> getRoomDevicesStream() {
    return _database.child('rooms').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return {'rooms': <String, dynamic>{}};
      return {'rooms': _convertToMapStringDynamic(data)};
    });
  }

  Map<String, dynamic> _convertToMapStringDynamic(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is Map) {
        result[key.toString()] = _convertToMapStringDynamic(value);
      } else {
        result[key.toString()] = value;
      }
    });
    return result;
  }

  Stream<SensorData> getSensorDataStream() {
    return _database.child('device/sensorData/environment').onValue.map((
      event,
    ) {
      final data = event.snapshot.value;
      if (data == null) return SensorData.empty();
      try {
        return SensorData.fromMap(Map<String, dynamic>.from(data as Map));
      } catch (_) {
        return SensorData.empty();
      }
    });
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;

    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }

    return 0.0;
  }

  @override
  Stream<bool> getConnectionStatus() {
    return _database.child('.info/connected').onValue.map((event) {
      return event.snapshot.value == true;
    });
  }

  DateTime _parseFirestoreTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();

    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }

    if (timestamp is String) {
      try {
        if (timestamp.contains('T')) {
          return DateTime.parse(timestamp);
        }

        if (timestamp.contains(' at ')) {
          final parts = timestamp.split(' at ');
          if (parts.length == 2) {
            final datePart = parts[0];
            final timePart = parts[1].split(' ')[0];

            final dateTime = DateFormat(
              'dd MMM yyyy HH:mm:ss',
            ).parse('$datePart $timePart');
            return dateTime;
          }
        }

        return DateTime.parse(timestamp);
      } catch (e) {
        return DateTime.now();
      }
    }

    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }

    return DateTime.now();
  }

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    try {
      final query = FirebaseFirestore.instance
          .collection('sensorLogs')
          .where('timestamp', isGreaterThanOrEqualTo: startDate)
          .where('timestamp', isLessThan: endDate)
          .orderBy('timestamp', descending: false)
          .limit(limit);

      final querySnapshot = await query.get();
      final List<HistoricalMcbData> historyData = [];

      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          final historicalData = _parseHistoricalData(data, doc.id);
          historyData.add(historicalData);
        } catch (e) {
          debugPrint('Error parsing doc ${doc.id}: $e');
          continue;
        }
      }

      return historyData;
    } catch (e) {
      throw Exception('Failed to fetch historical data: $e');
    }
  }

  HistoricalMcbData _parseHistoricalData(Map<String, dynamic> data, String id) {
    try {
      final timestamp = _parseFirestoreTimestamp(data['timestamp']);

      final powerData = data['power'] as Map<String, dynamic>? ?? {};
      final envData = data['environment'] as Map<String, dynamic>? ?? {};

      final mcb1 = McbData(
        connected: powerData['connected'] == true,
        voltage: _parseDouble(powerData['voltage']),
        current: _parseDouble(powerData['current']),
        power: _parseDouble(powerData['power']),
        energy: _parseDouble(powerData['energy']),
        lastUpdate: timestamp.millisecondsSinceEpoch,
      );
      final sensorData = SensorData(
        temperature: _parseDouble(envData['temperature']),
        humidity: _parseDouble(envData['humidity']),
      );

      return HistoricalMcbData(
        id: id,
        timestamp: timestamp,
        mcb1: mcb1,
        sensorData: sensorData,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<List<HistoricalMcbData>> getTodayHistoryData() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return await getHistoricalData(
      startDate: startOfDay,
      endDate: endOfDay,
      limit: 288,
    );
  }

  Future<List<HistoricalMcbData>> getWeekHistoryData() async {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(const Duration(days: 7));

    return await getHistoricalData(
      startDate: startDate,
      endDate: endDate,
      limit: 500,
    );
  }

  Future<List<HistoricalMcbData>> getMonthHistoryData() async {
    final endDate = DateTime.now();
    final startDate = DateTime(endDate.year, endDate.month - 1, endDate.day);

    return await getHistoricalData(
      startDate: startDate,
      endDate: endDate,
      limit: 1000,
    );
  }

  Future<List<HistoricalMcbData>> getAllHistoryData() async {
    try {
      final query = FirebaseFirestore.instance
          .collection('energyData')
          .orderBy('timestamp', descending: false);

      final querySnapshot = await query.get();

      final List<HistoricalMcbData> historyData = [];

      for (final doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          final historicalData = _parseHistoricalData(data, doc.id);
          historyData.add(historicalData);
        } catch (e) {
          continue;
        }
      }

      return historyData;
    } catch (e) {
      throw Exception('Failed to fetch all historical data: $e');
    }
  }

  Future<List<HistoricalMcbData>> getHistoricalDataSafe({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 100,
  }) async {
    try {
      final query = FirebaseFirestore.instance
          .collection('energyData')
          .where('timestamp', isGreaterThanOrEqualTo: startDate)
          .where('timestamp', isLessThanOrEqualTo: endDate)
          .orderBy('timestamp', descending: false)
          .limit(limit);

      final snapshot = await query.get();

      final List<HistoricalMcbData> result = [];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final historicalData = HistoricalMcbData.fromFirestore(data, doc.id);
          result.add(historicalData);
        } catch (e) {
          continue;
        }
      }
      result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return result;
    } catch (e) {
      return [];
    }
  }

  Future<List<HistoricalMcbData>> getAllHistoryDataSafe() async {
    try {
      final query = FirebaseFirestore.instance
          .collection('energyData')
          .orderBy('timestamp', descending: false)
          .limit(500);

      final snapshot = await query.get();

      final List<HistoricalMcbData> result = [];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final historicalData = HistoricalMcbData.fromFirestore(data, doc.id);
          result.add(historicalData);
        } catch (e) {
          continue;
        }
      }
      result.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return result;
    } catch (e) {
      return [];
    }
  }

  Future<void> debugFirestoreData() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('energyData')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;

        final data = doc.data();
        data.forEach((key, value) {});
      } else {
        throw Exception('No documents found in energyData collection');
      }
    } catch (e) {
      throw Exception('Failed to debug Firestore data: $e');
    }
  }

  Future<void> saveHistoricalData(McbDataCollection collection) async {
    try {
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      final historicalData = HistoricalMcbData.fromMcbCollection(
        collection,
        docId,
      );

      await FirebaseFirestore.instance
          .collection('energyData')
          .doc(docId)
          .set(historicalData.toFirestore());
    } catch (e) {
      throw Exception('Failed to save historical data: $e');
    }
  }

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {
    try {
      final path = 'commands/rooms/$roomKey/$deviceKey';
      if (supportsBrightness) {
        await _database.child(path).set({
          'state': isOn,
          'brightness': brightness,
        });
      } else {
        await _database.child(path).set(isOn);
      }
    } catch (e) {
      throw Exception('Failed to control device: $e');
    }
  }
}
