# Clean Architecture Data Layer Tahap 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ganti `FirebaseService` dengan Firebase data source dan repository implementation tanpa mengubah Firebase path, payload command, stream, history query, BLoC, atau UI.

**Architecture:** Firebase SDK hanya hidup di `AppDependencies` dan data source feature. Repository implementation memenuhi contract domain serta delegasi ke data source interface. Parser yang sebelumnya private menjadi top-level function di data source agar unit test bisa memverifikasi behavior tanpa Firebase emulator.

**Tech Stack:** Flutter, Dart 3.8.1, flutter_bloc 9.1.1, firebase_database 10.5.0, cloud_firestore 4.15.0, flutter_test.

## Global Constraints

- Jangan ubah Firebase path `device/sensorData`, `.info/connected`, `rooms`, `commands/rooms/<roomKey>/<deviceKey>`, `sensorLogs`, atau `energyData`.
- Jangan ubah payload state-only `bool` atau dimmable `{state, brightness}`.
- Jangan ubah optimistic command, pending, timeout, rollback, confirmed `/rooms`, BLoC event/state, route, atau widget behavior.
- Jangan pindahkan entity dari `lib/models/model.dart` pada tahap ini.
- Jangan menambah package dependency, Firebase rule, Firebase options, atau UI copy.
- Pertahankan method legacy history, raw DB, dan sensor stream walau belum dipakai app source.
- Jangan commit tanpa instruksi eksplisit pengguna.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/features/monitoring/data/datasources/firebase_value_parser.dart` | Normalisasi map Firebase dan parse number. |
| `lib/features/monitoring/data/datasources/firebase_monitoring_data_source.dart` | Telemetry, connection, raw DB, sensor stream. |
| `lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart` | Room stream dan command write. |
| `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart` | Delegasi contract monitoring ke dua data source. |
| `lib/features/history/data/datasources/firebase_history_data_source.dart` | Query, mapping, dan method legacy Firestore. |
| `lib/features/history/data/repositories/history_repository_impl.dart` | Delegasi contract history ke data source. |
| `lib/app/app_dependencies.dart` | Membuat Firebase reference, data source, dan repository implementation. |
| `test/firebase_monitoring_data_source_test.dart` | Parser telemetry dan map helper. |
| `test/firebase_room_device_data_source_test.dart` | Parser room, path, dan payload command. |
| `test/firebase_history_data_source_test.dart` | Mapper history dan collection constant. |
| `test/repository_implementation_test.dart` | Delegasi repository dengan fake data source. |
| `test/architecture_boundary_test.dart` | Boundary Firebase dan penghapusan service lama. |

### Task 1: Monitoring dan Room Data Source

**Files:**
- Create: `lib/features/monitoring/data/datasources/firebase_value_parser.dart`
- Create: `lib/features/monitoring/data/datasources/firebase_monitoring_data_source.dart`
- Create: `lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart`
- Test: `test/firebase_monitoring_data_source_test.dart`
- Test: `test/firebase_room_device_data_source_test.dart`

**Interfaces:**

```dart
abstract interface class MonitoringDataSource {
  Stream<McbDataCollection> getMonitoringDataStream();
  Stream<bool> getConnectionStatus();
}

abstract interface class RoomDeviceDataSource {
  Stream<Map<String, dynamic>> getRoomDevicesStream();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}

McbDataCollection parseMonitoringData(dynamic value);
Map<String, dynamic> parseRoomDevicesData(dynamic value);
String roomDeviceCommandPath(String roomKey, String deviceKey);
Object roomDeviceCommandPayload({
  required bool isOn,
  required int brightness,
  required bool supportsBrightness,
});
```

- [ ] **Step 1: Write failing parser tests**

Create `test/firebase_monitoring_data_source_test.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseMonitoringData returns empty data for malformed root', () {
    final result = parseMonitoringData('invalid');

    expect(result.mcb1.connected, isFalse);
    expect(result.mcb1.voltage, 0);
    expect(result.sensorData.temperature, 0);
  });

  test('parseMonitoringData normalizes numeric Firebase values', () {
    final result = parseMonitoringData({
      'environment': {
        'temperature': '28.5',
        'humidity': 60,
        'connected': true,
      },
      'power': {
        'connected': true,
        'voltage': 220,
        'current': '1.25',
        'power': 275.5,
        'energy': '12.75',
      },
    });

    expect(result.sensorData.temperature, 28.5);
    expect(result.sensorData.humidity, 60);
    expect(result.sensorData.connected, isTrue);
    expect(result.mcb1.connected, isTrue);
    expect(result.mcb1.voltage, 220);
    expect(result.mcb1.current, 1.25);
    expect(result.mcb1.power, 275.5);
    expect(result.mcb1.energy, 12.75);
  });
}
```

Create `test/firebase_room_device_data_source_test.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseRoomDevicesData retains rooms wrapper for valid Firebase map', () {
    final result = parseRoomDevicesData({
      'teras': {'lampu': true},
    });

    expect(result, {
      'rooms': {
        'teras': {'lampu': true},
      },
    });
  });

  test('parseRoomDevicesData returns empty rooms for malformed value', () {
    expect(parseRoomDevicesData('invalid'), {
      'rooms': <String, dynamic>{},
    });
  });

  test('room device command uses canonical path and dimmable payload', () {
    expect(
      roomDeviceCommandPath('dapur', 'lampu'),
      'commands/rooms/dapur/lampu',
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

  test('state-only command retains bool payload', () {
    expect(
      roomDeviceCommandPayload(
        isOn: false,
        brightness: 0,
        supportsBrightness: false,
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/firebase_monitoring_data_source_test.dart test/firebase_room_device_data_source_test.dart
```

Expected: FAIL because data source files do not exist.

- [ ] **Step 3: Add Firebase value parser**

Create `lib/features/monitoring/data/datasources/firebase_value_parser.dart`:

```dart
Map<String, dynamic> normalizeFirebaseMap(Map<dynamic, dynamic> map) {
  final result = <String, dynamic>{};
  map.forEach((key, value) {
    if (value is Map) {
      result[key.toString()] = normalizeFirebaseMap(value);
    } else {
      result[key.toString()] = value;
    }
  });
  return result;
}

double parseFirebaseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}
```

- [ ] **Step 4: Add monitoring data source**

Create `lib/features/monitoring/data/datasources/firebase_monitoring_data_source.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/models/model.dart';
import 'package:firebase_database/firebase_database.dart';

abstract interface class MonitoringDataSource {
  Stream<McbDataCollection> getMonitoringDataStream();
  Stream<bool> getConnectionStatus();
}

McbDataCollection parseMonitoringData(dynamic value) {
  if (value is! Map) return McbDataCollection.empty();

  final sensorRoot = normalizeFirebaseMap(value);
  final environment = sensorRoot['environment'];
  final power = sensorRoot['power'];
  final environmentMap = environment is Map
      ? normalizeFirebaseMap(environment)
      : <String, dynamic>{};
  final powerMap = power is Map
      ? normalizeFirebaseMap(power)
      : <String, dynamic>{};

  return McbDataCollection(
    mcb1: McbData(
      connected: powerMap['connected'] == true,
      voltage: parseFirebaseDouble(powerMap['voltage']),
      current: parseFirebaseDouble(powerMap['current']),
      power: parseFirebaseDouble(powerMap['power']),
      energy: parseFirebaseDouble(powerMap['energy']),
    ),
    sensorData: SensorData(
      temperature: parseFirebaseDouble(environmentMap['temperature']),
      humidity: parseFirebaseDouble(environmentMap['humidity']),
      connected: environmentMap['connected'] == true,
    ),
  );
}

class FirebaseMonitoringDataSource implements MonitoringDataSource {
  final DatabaseReference database;

  FirebaseMonitoringDataSource({required this.database});

  @override
  Stream<McbDataCollection> getMonitoringDataStream() {
    return database.child('device/sensorData').onValue.map((event) {
      return parseMonitoringData(event.snapshot.value);
    });
  }

  Stream<Map<String, dynamic>> getRawDatabaseStream() {
    return database.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <String, dynamic>{};
      return normalizeFirebaseMap(data);
    });
  }

  Stream<SensorData> getSensorDataStream() {
    return database.child('device/sensorData/environment').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return SensorData.empty();
      try {
        return SensorData.fromMap(Map<String, dynamic>.from(data as Map));
      } catch (_) {
        return SensorData.empty();
      }
    });
  }

  @override
  Stream<bool> getConnectionStatus() {
    return database.child('.info/connected').onValue.map((event) {
      return event.snapshot.value == true;
    });
  }
}
```

- [ ] **Step 5: Add room-device data source**

Create `lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:firebase_database/firebase_database.dart';

abstract interface class RoomDeviceDataSource {
  Stream<Map<String, dynamic>> getRoomDevicesStream();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}

Map<String, dynamic> parseRoomDevicesData(dynamic value) {
  if (value is! Map) return {'rooms': <String, dynamic>{}};
  return {'rooms': normalizeFirebaseMap(value)};
}

String roomDeviceCommandPath(String roomKey, String deviceKey) {
  return 'commands/rooms/$roomKey/$deviceKey';
}

Object roomDeviceCommandPayload({
  required bool isOn,
  required int brightness,
  required bool supportsBrightness,
}) {
  if (!supportsBrightness) return isOn;
  return {'state': isOn, 'brightness': brightness};
}

class FirebaseRoomDeviceDataSource implements RoomDeviceDataSource {
  final DatabaseReference database;

  FirebaseRoomDeviceDataSource({required this.database});

  @override
  Stream<Map<String, dynamic>> getRoomDevicesStream() {
    return database.child('rooms').onValue.map((event) {
      return parseRoomDevicesData(event.snapshot.value);
    });
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
      await database.child(roomDeviceCommandPath(roomKey, deviceKey)).set(
        roomDeviceCommandPayload(
          isOn: isOn,
          brightness: brightness,
          supportsBrightness: supportsBrightness,
        ),
      );
    } catch (error) {
      throw Exception('Failed to control device: $error');
    }
  }
}
```

- [ ] **Step 6: Run focused tests**

Run:

```powershell
flutter test test/firebase_monitoring_data_source_test.dart test/firebase_room_device_data_source_test.dart
```

Expected: PASS.

- [ ] **Step 7: Review intended diff**

Run:

```powershell
git diff -- lib/features/monitoring/data test/firebase_monitoring_data_source_test.dart test/firebase_room_device_data_source_test.dart
```

Expected: telemetry paths, room path, command path, and payload match former `FirebaseService`.

### Task 2: History Data Source dan Mapper

**Files:**
- Create: `lib/features/history/data/datasources/firebase_history_data_source.dart`
- Test: `test/firebase_history_data_source_test.dart`

**Interfaces:**

```dart
abstract interface class HistoryDataSource {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}

const canonicalHistoryCollection = 'sensorLogs';
const legacyHistoryCollection = 'energyData';
DateTime parseFirestoreTimestamp(dynamic timestamp);
HistoricalMcbData parseHistoricalMcbData(Map<String, dynamic> data, String id);
```

- [ ] **Step 1: Write failing mapper tests**

Create `test/firebase_history_data_source_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
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

  test('parseHistoricalMcbData maps canonical sensorLogs record', () {
    final result = parseHistoricalMcbData({
      'timestamp': Timestamp(1, 0),
      'power': {
        'connected': true,
        'voltage': 220,
        'current': '1.5',
        'power': 330,
        'energy': 4.25,
      },
      'environment': {
        'temperature': 27.5,
        'humidity': '60',
      },
    }, 'record-1');

    expect(result.id, 'record-1');
    expect(result.timestamp, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(result.mcb1!.connected, isTrue);
    expect(result.mcb1!.current, 1.5);
    expect(result.sensorData!.temperature, 27.5);
    expect(result.sensorData!.humidity, 60);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/firebase_history_data_source_test.dart
```

Expected: FAIL because history data source does not exist.

- [ ] **Step 3: Add history data source**

Create `lib/features/history/data/datasources/firebase_history_data_source.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/models/model.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

const canonicalHistoryCollection = 'sensorLogs';
const legacyHistoryCollection = 'energyData';

abstract interface class HistoryDataSource {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}

DateTime parseFirestoreTimestamp(dynamic timestamp) {
  if (timestamp == null) return DateTime.now();
  if (timestamp is Timestamp) return timestamp.toDate();
  if (timestamp is String) {
    try {
      if (timestamp.contains('T')) return DateTime.parse(timestamp);
      if (timestamp.contains(' at ')) {
        final parts = timestamp.split(' at ');
        if (parts.length == 2) {
          final datePart = parts[0];
          final timePart = parts[1].split(' ')[0];
          return DateFormat('dd MMM yyyy HH:mm:ss').parse('$datePart $timePart');
        }
      }
      return DateTime.parse(timestamp);
    } catch (_) {
      return DateTime.now();
    }
  }
  if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime.now();
}

HistoricalMcbData parseHistoricalMcbData(
  Map<String, dynamic> data,
  String id,
) {
  final timestamp = parseFirestoreTimestamp(data['timestamp']);
  final powerData = data['power'] as Map<String, dynamic>? ?? {};
  final environmentData = data['environment'] as Map<String, dynamic>? ?? {};

  return HistoricalMcbData(
    id: id,
    timestamp: timestamp,
    mcb1: McbData(
      connected: powerData['connected'] == true,
      voltage: parseFirebaseDouble(powerData['voltage']),
      current: parseFirebaseDouble(powerData['current']),
      power: parseFirebaseDouble(powerData['power']),
      energy: parseFirebaseDouble(powerData['energy']),
      lastUpdate: timestamp.millisecondsSinceEpoch,
    ),
    sensorData: SensorData(
      temperature: parseFirebaseDouble(environmentData['temperature']),
      humidity: parseFirebaseDouble(environmentData['humidity']),
    ),
  );
}

class FirebaseHistoryDataSource implements HistoryDataSource {
  final FirebaseFirestore firestore;

  FirebaseHistoryDataSource({required this.firestore});

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
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
      final historyData = <HistoricalMcbData>[];

      for (final doc in querySnapshot.docs) {
        try {
          historyData.add(parseHistoricalMcbData(doc.data(), doc.id));
        } catch (error) {
          debugPrint('Error parsing doc ${doc.id}: $error');
        }
      }
      return historyData;
    } catch (error) {
      throw Exception('Failed to fetch historical data: $error');
    }
  }

  Future<List<HistoricalMcbData>> getTodayHistoryData() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return getHistoricalData(
      startDate: startOfDay,
      endDate: startOfDay.add(const Duration(days: 1)),
      limit: 288,
    );
  }

  Future<List<HistoricalMcbData>> getWeekHistoryData() async {
    final endDate = DateTime.now();
    return getHistoricalData(
      startDate: endDate.subtract(const Duration(days: 7)),
      endDate: endDate,
      limit: 500,
    );
  }

  Future<List<HistoricalMcbData>> getMonthHistoryData() async {
    final endDate = DateTime.now();
    return getHistoricalData(
      startDate: DateTime(endDate.year, endDate.month - 1, endDate.day),
      endDate: endDate,
      limit: 1000,
    );
  }

  Future<List<HistoricalMcbData>> getAllHistoryData() async {
    try {
      final querySnapshot = await firestore
          .collection(legacyHistoryCollection)
          .orderBy('timestamp', descending: false)
          .get();
      final historyData = <HistoricalMcbData>[];
      for (final doc in querySnapshot.docs) {
        try {
          historyData.add(parseHistoricalMcbData(doc.data(), doc.id));
        } catch (_) {}
      }
      return historyData;
    } catch (error) {
      throw Exception('Failed to fetch all historical data: $error');
    }
  }

  Future<List<HistoricalMcbData>> getHistoricalDataSafe({
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
      final result = <HistoricalMcbData>[];
      for (final doc in snapshot.docs) {
        try {
          result.add(HistoricalMcbData.fromFirestore(doc.data(), doc.id));
        } catch (_) {}
      }
      result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<HistoricalMcbData>> getAllHistoryDataSafe() async {
    try {
      final snapshot = await firestore
          .collection(legacyHistoryCollection)
          .orderBy('timestamp', descending: false)
          .limit(500)
          .get();
      final result = <HistoricalMcbData>[];
      for (final doc in snapshot.docs) {
        try {
          result.add(HistoricalMcbData.fromFirestore(doc.data(), doc.id));
        } catch (_) {}
      }
      result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return result;
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

  Future<void> saveHistoricalData(McbDataCollection collection) async {
    try {
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      final historicalData = HistoricalMcbData.fromMcbCollection(
        collection,
        docId,
      );
      await firestore
          .collection(legacyHistoryCollection)
          .doc(docId)
          .set(historicalData.toFirestore());
    } catch (error) {
      throw Exception('Failed to save historical data: $error');
    }
  }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/firebase_history_data_source_test.dart
```

Expected: PASS.

- [ ] **Step 5: Review path and query parity**

Run:

```powershell
rg "sensorLogs|energyData|isLessThan: endDate|isLessThanOrEqualTo: endDate" lib/features/history/data/datasources/firebase_history_data_source.dart
```

Expected: canonical `sensorLogs` uses `isLessThan`; legacy safe query uses `isLessThanOrEqualTo`.

### Task 3: Repository Implementations

**Files:**
- Create: `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart`
- Create: `lib/features/history/data/repositories/history_repository_impl.dart`
- Create: `test/repository_implementation_test.dart`

**Interfaces:**

```dart
class MonitoringRepositoryImpl implements MonitoringRepository {
  final MonitoringDataSource monitoringDataSource;
  final RoomDeviceDataSource roomDeviceDataSource;
}

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryDataSource historyDataSource;
}
```

- [ ] **Step 1: Write failing delegation tests**

Create `test/repository_implementation_test.dart`:

```dart
import 'dart:async';

import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/repositories/history_repository_impl.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:esh/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonitoringDataSource implements MonitoringDataSource {
  final monitoringController = StreamController<McbDataCollection>.broadcast();
  final connectionController = StreamController<bool>.broadcast();

  @override
  Stream<bool> getConnectionStatus() => connectionController.stream;

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => monitoringController.stream;

  Future<void> close() async {
    await monitoringController.close();
    await connectionController.close();
  }
}

class FakeRoomDeviceDataSource implements RoomDeviceDataSource {
  final roomController = StreamController<Map<String, dynamic>>.broadcast();
  List<Object>? command;

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {
    command = [roomKey, deviceKey, isOn, brightness, supportsBrightness];
  }

  @override
  Stream<Map<String, dynamic>> getRoomDevicesStream() => roomController.stream;

  Future<void> close() => roomController.close();
}

class FakeHistoryDataSource implements HistoryDataSource {
  DateTime? startDate;
  DateTime? endDate;
  int? receivedLimit;

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    this.startDate = startDate;
    this.endDate = endDate;
    receivedLimit = limit;
    return const [];
  }
}

void main() {
  test('monitoring repository delegates command unchanged', () async {
    final monitoringDataSource = FakeMonitoringDataSource();
    final roomDeviceDataSource = FakeRoomDeviceDataSource();
    final repository = MonitoringRepositoryImpl(
      monitoringDataSource: monitoringDataSource,
      roomDeviceDataSource: roomDeviceDataSource,
    );

    await repository.controlRoomDevice('dapur', 'lampu', true, 75, true);

    expect(roomDeviceDataSource.command, ['dapur', 'lampu', true, 75, true]);

    await monitoringDataSource.close();
    await roomDeviceDataSource.close();
  });

  test('history repository delegates full date query unchanged', () async {
    final dataSource = FakeHistoryDataSource();
    final repository = HistoryRepositoryImpl(historyDataSource: dataSource);
    final startDate = DateTime(2026, 7, 1);
    final endDate = DateTime(2026, 7, 2);

    await repository.getHistoricalData(
      startDate: startDate,
      endDate: endDate,
      limit: 200,
    );

    expect(dataSource.startDate, startDate);
    expect(dataSource.endDate, endDate);
    expect(dataSource.receivedLimit, 200);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/repository_implementation_test.dart
```

Expected: FAIL because repository implementation files do not exist.

- [ ] **Step 3: Add repository implementations**

Create `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/models/model.dart';

class MonitoringRepositoryImpl implements MonitoringRepository {
  final MonitoringDataSource monitoringDataSource;
  final RoomDeviceDataSource roomDeviceDataSource;

  MonitoringRepositoryImpl({
    required this.monitoringDataSource,
    required this.roomDeviceDataSource,
  });

  @override
  Stream<McbDataCollection> getMonitoringDataStream() {
    return monitoringDataSource.getMonitoringDataStream();
  }

  @override
  Stream<Map<String, dynamic>> getRoomDevicesStream() {
    return roomDeviceDataSource.getRoomDevicesStream();
  }

  @override
  Stream<bool> getConnectionStatus() {
    return monitoringDataSource.getConnectionStatus();
  }

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) {
    return roomDeviceDataSource.controlRoomDevice(
      roomKey,
      deviceKey,
      isOn,
      brightness,
      supportsBrightness,
    );
  }
}
```

Create `lib/features/history/data/repositories/history_repository_impl.dart`:

```dart
import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/models/model.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryDataSource historyDataSource;

  HistoryRepositoryImpl({required this.historyDataSource});

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) {
    return historyDataSource.getHistoricalData(
      startDate: startDate,
      endDate: endDate,
      limit: limit,
    );
  }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/repository_implementation_test.dart
```

Expected: PASS.

- [ ] **Step 5: Check repository Firebase boundary**

Run:

```powershell
rg "package:(firebase_database|cloud_firestore)" lib/features/*/data/repositories
```

Expected: no match.

### Task 4: Composition Root, Service Removal, Boundary Tests

**Files:**
- Modify: `lib/app/app_dependencies.dart`
- Delete: `lib/services/firebase_service.dart`
- Modify: `test/architecture_boundary_test.dart`
- Modify: `test/app_dependencies_test.dart`

- [ ] **Step 1: Write failing architecture tests**

Add to `test/architecture_boundary_test.dart`:

```dart
test('legacy FirebaseService file is removed', () {
  expect(File('lib/services/firebase_service.dart').existsSync(), isFalse);
});

test('repository implementations avoid Firebase SDK imports', () {
  const repositoryFiles = [
    'lib/features/monitoring/data/repositories/monitoring_repository_impl.dart',
    'lib/features/history/data/repositories/history_repository_impl.dart',
  ];

  for (final file in repositoryFiles) {
    final source = readProjectFile(file);
    expect(source, isNot(contains('package:firebase_database/')), reason: file);
    expect(source, isNot(contains('package:cloud_firestore/')), reason: file);
  }
});

test('Firebase SDK imports remain outside BLoC and screen', () {
  const applicationFiles = [
    'lib/bloc/monitoring/monitoring_bloc.dart',
    'lib/bloc/history/history_bloc.dart',
    'lib/screen/monitoring.dart',
    'lib/screen/control.dart',
    'lib/screen/history.dart',
  ];

  for (final file in applicationFiles) {
    final source = readProjectFile(file);
    expect(source, isNot(contains('package:firebase_database/')), reason: file);
    expect(source, isNot(contains('package:cloud_firestore/')), reason: file);
  }
});
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: FAIL because old service exists and repository implementation files are absent.

- [ ] **Step 3: Rewire AppDependencies**

Replace `lib/app/app_dependencies.dart` with:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/repositories/history_repository_impl.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:firebase_database/firebase_database.dart';

class AppDependencies {
  final MonitoringRepository monitoringRepository;
  final HistoryRepository historyRepository;

  const AppDependencies({
    required this.monitoringRepository,
    required this.historyRepository,
  });

  factory AppDependencies.firebase() {
    final database = FirebaseDatabase.instance.ref();
    final firestore = FirebaseFirestore.instance;
    final monitoringDataSource = FirebaseMonitoringDataSource(
      database: database,
    );
    final roomDeviceDataSource = FirebaseRoomDeviceDataSource(
      database: database,
    );
    final historyDataSource = FirebaseHistoryDataSource(firestore: firestore);

    return AppDependencies(
      monitoringRepository: MonitoringRepositoryImpl(
        monitoringDataSource: monitoringDataSource,
        roomDeviceDataSource: roomDeviceDataSource,
      ),
      historyRepository: HistoryRepositoryImpl(
        historyDataSource: historyDataSource,
      ),
    );
  }
}
```

- [ ] **Step 4: Delete old service**

Verify exact target first:

```powershell
Test-Path -LiteralPath "lib\services\firebase_service.dart"
```

Expected: `True`.

Delete only old service:

```powershell
Remove-Item -LiteralPath "lib\services\firebase_service.dart"
```

Expected: file removed.

- [ ] **Step 5: Update dependency test name only if needed**

Keep fake contract injection in `test/app_dependencies_test.dart`. Do not call `AppDependencies.firebase()` from test, because factory creates real Firebase SDK singleton. Rename `FakeRepository` to `FakeAppRepository` only if name conflicts after imports; behavior and assertions remain unchanged.

- [ ] **Step 6: Run integration-focused tests**

Run:

```powershell
flutter test test/app_dependencies_test.dart test/architecture_boundary_test.dart test/repository_implementation_test.dart test/monitoring_bloc_test.dart test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 7: Check old service reference removal**

Run:

```powershell
rg "FirebaseService|services/firebase_service.dart" lib test
```

Expected: no match.

### Task 5: Full Verification

**Files:**
- Modify only files reported by formatter among files changed in Tasks 1-4.

- [ ] **Step 1: Format changed Dart files**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
```

Expected: exit code `0`.

If nonzero, run:

```powershell
dart format lib test
```

Then restore any unrelated format-only file and rerun formatter check on changed scope until exit code `0`.

- [ ] **Step 2: Static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 3: Full test suite**

Run:

```powershell
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Android debug build**

Run:

```powershell
flutter build apk --debug
```

Expected: `build\app\outputs\flutter-apk\app-debug.apk` exists.

- [ ] **Step 5: Final scope audit**

Run:

```powershell
git diff --check
git status --short
git diff --stat
```

Expected: no whitespace errors; no `lib/services/firebase_service.dart`; only stage 2 Dart/test/doc changes plus existing stage 1 changes.

- [ ] **Step 6: Do not commit**

User has not requested a commit. Leave changes unstaged.

## Self-Review

- Spec coverage: three Firebase data sources, two repository implementations, DI wiring, legacy preservation, parser behavior, command shape/path, architecture boundary, and full verification included.
- Placeholder scan: none.
- Type consistency: `MonitoringDataSource`, `RoomDeviceDataSource`, `HistoryDataSource`, `MonitoringRepositoryImpl`, `HistoryRepositoryImpl`, and helper signatures match every task.
- Scope boundary: entity extraction, model split, use cases, typed device state, Firebase schema/rule changes, and UI changes excluded.
