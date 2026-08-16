# Clean Architecture Domain Entity Tahap 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pindahkan entity monitoring/history ke domain murni dan pindahkan parsing/serialisasi schema Firebase ke mapper data layer tanpa mengubah behavior aplikasi.

**Architecture:** Empat entity immutable hidup di feature domain, tanpa `Map`, `dynamic`, Firebase, Flutter, atau data import. Mapper data layer menjadi satu-satunya tempat yang mengetahui raw Realtime Database dan schema canonical/legacy Firestore. Data source tetap stream/query Firebase sama, tetapi memanggil mapper; BLoC/UI/repository contract menggunakan entity domain.

**Tech Stack:** Flutter, Dart 3.8.1, flutter_bloc 9.1.1, firebase_database 10.5.0, cloud_firestore 4.15.0, intl 0.20.2, flutter_test.

## Global Constraints

- Jangan ubah Firebase path `device/sensorData`, `.info/connected`, `rooms`, `commands/rooms/<roomKey>/<deviceKey>`, `sensorLogs`, atau `energyData`.
- Jangan ubah payload command state-only atau dimmable.
- Jangan ubah query history canonical half-open, legacy safe inclusive, ordering, limit, error text, or safe empty-list behavior.
- Jangan ubah optimistic command, pending, timeout, rollback, BLoC/UI behavior, route, atau visual UI.
- Pertahankan `DateTime.now()` fallback timestamp, nullable legacy history fields, sensor alias, `lastUpdate`, dan schema legacy write.
- Jangan migrasikan `lib/models/device_config.dart`.
- Jangan menambah package dependency, Firebase rule, Firebase options, atau UI copy.
- Jangan commit tanpa instruksi eksplisit pengguna.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/features/monitoring/domain/entities/sensor_data.dart` | Entity sensor dan rule heat index/comfort. |
| `lib/features/monitoring/domain/entities/mcb_data.dart` | Entity MCB immutable. |
| `lib/features/monitoring/domain/entities/mcb_data_collection.dart` | Aggregate MCB dan sensor. |
| `lib/features/history/domain/entities/historical_mcb_data.dart` | Entity history nullable legacy metrics. |
| `lib/features/monitoring/data/mappers/realtime_monitoring_mapper.dart` | Parse canonical telemetry dan alias legacy sensor. |
| `lib/features/history/data/mappers/firestore_history_mapper.dart` | Parse/serialize canonical dan legacy Firestore history. |
| `lib/models/model.dart` | Delete only after all imports migrate. |
| `test/domain_entities_test.dart` | Pure entity behavior. |
| `test/realtime_monitoring_mapper_test.dart` | Realtime schema behavior. |
| `test/firestore_history_mapper_test.dart` | Canonical/legacy mapping and serialization. |
| `test/architecture_boundary_test.dart` | Domain purity and deleted model enforcement. |

### Task 1: Pure Monitoring Domain Entities

**Files:**
- Create: `lib/features/monitoring/domain/entities/sensor_data.dart`
- Create: `lib/features/monitoring/domain/entities/mcb_data.dart`
- Create: `lib/features/monitoring/domain/entities/mcb_data_collection.dart`
- Create: `test/domain_entities_test.dart`

**Produces:**

```dart
class SensorData {
  const SensorData({
    required this.temperature,
    required this.humidity,
    this.connected = false,
  });

  factory SensorData.empty();
  final double temperature;
  final double humidity;
  final bool connected;
  double get heatIndex;
  String get comfortLevel;
}

class McbData {
  const McbData({
    required this.connected,
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    this.lastUpdate = 0,
  });

  factory McbData.empty();
  final bool connected;
  final double voltage;
  final double current;
  final double power;
  final double energy;
  final int lastUpdate;
  McbData copyWith(...);
}

class McbDataCollection {
  const McbDataCollection({required this.mcb1, this.sensorData = ...});

  factory McbDataCollection.empty();
  final McbData mcb1;
  final SensorData sensorData;
  McbDataCollection copyWith(...);
  double get totalCurrent;
  double get totalPower;
  double get totalEnergy;
}
```

- [ ] **Step 1: Write failing entity tests**

Create `test/domain_entities_test.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty monitoring entities retain previous zero defaults', () {
    expect(SensorData.empty().temperature, 0);
    expect(SensorData.empty().humidity, 0);
    expect(SensorData.empty().connected, isFalse);
    expect(McbData.empty().voltage, 0);
    expect(McbDataCollection.empty().mcb1.energy, 0);
  });

  test('SensorData retains heat index and comfort rules', () {
    const comfortable = SensorData(temperature: 25, humidity: 60);
    const hot = SensorData(temperature: 31, humidity: 60);

    expect(comfortable.heatIndex, 25);
    expect(comfortable.comfortLevel, 'Nyaman');
    expect(hot.comfortLevel, 'Panas');
  });

  test('McbData copyWith and collection aggregates preserve values', () {
    const mcb = McbData(
      connected: true,
      voltage: 220,
      current: 1.5,
      power: 330,
      energy: 12.5,
      lastUpdate: 123,
    );
    final updated = mcb.copyWith(power: 400);
    final collection = McbDataCollection(mcb1: updated);

    expect(updated.power, 400);
    expect(updated.lastUpdate, 123);
    expect(collection.totalCurrent, 1.5);
    expect(collection.totalPower, 400);
    expect(collection.totalEnergy, 12.5);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/domain_entities_test.dart
```

Expected: FAIL because entity files do not exist.

- [ ] **Step 3: Create `SensorData`**

Create `lib/features/monitoring/domain/entities/sensor_data.dart` with existing constructor, `empty()`, `heatIndex`, and `comfortLevel` logic from `lib/models/model.dart:5-72`. Remove all parsing factory/helper code. Preserve exact thresholds and return text.

- [ ] **Step 4: Create `McbData`**

Create `lib/features/monitoring/domain/entities/mcb_data.dart` with existing constructor, `empty()`, `copyWith()`, and `toString()` from `lib/models/model.dart:74-161`. Remove `fromMap()`, `toMap()`, number parser, and int parser.

- [ ] **Step 5: Create `McbDataCollection`**

Create `lib/features/monitoring/domain/entities/mcb_data_collection.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

class McbDataCollection {
  final McbData mcb1;
  final SensorData sensorData;

  const McbDataCollection({
    required this.mcb1,
    this.sensorData = const SensorData(temperature: 0, humidity: 0),
  });

  factory McbDataCollection.empty() {
    return McbDataCollection(
      mcb1: McbData.empty(),
      sensorData: SensorData.empty(),
    );
  }

  McbDataCollection copyWith({McbData? mcb1, SensorData? sensorData}) {
    return McbDataCollection(
      mcb1: mcb1 ?? this.mcb1,
      sensorData: sensorData ?? this.sensorData,
    );
  }

  double get totalCurrent => mcb1.current;
  double get totalPower => mcb1.power;
  double get totalEnergy => mcb1.energy;
}
```

- [ ] **Step 6: Run entity tests**

Run:

```powershell
flutter test test/domain_entities_test.dart
```

Expected: PASS.

- [ ] **Step 7: Review domain purity**

Run:

```powershell
rg "Map<|dynamic|firebase|cloud_firestore|flutter" lib/features/monitoring/domain/entities
```

Expected: no match.

### Task 2: Historical Domain Entity and Realtime Mapper

**Files:**
- Create: `lib/features/history/domain/entities/historical_mcb_data.dart`
- Create: `lib/features/monitoring/data/mappers/realtime_monitoring_mapper.dart`
- Modify: `lib/features/monitoring/data/datasources/firebase_monitoring_data_source.dart`
- Create: `test/realtime_monitoring_mapper_test.dart`

**Consumes:** Monitoring domain entities; `normalizeFirebaseMap` and `parseFirebaseDouble`.

**Produces:**

```dart
McbDataCollection mapRealtimeMonitoringData(dynamic value);
SensorData mapRealtimeSensorData(dynamic value);
```

- [ ] **Step 1: Write failing mapper tests**

Create `test/realtime_monitoring_mapper_test.dart`:

```dart
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical telemetry maps numeric and nested Firebase values', () {
    final result = mapRealtimeMonitoringData({
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
    expect(result.mcb1.current, 1.25);
    expect(result.mcb1.lastUpdate, 0);
  });

  test('canonical telemetry malformed root stays empty', () {
    final result = mapRealtimeMonitoringData('invalid');

    expect(result.mcb1.energy, 0);
    expect(result.sensorData.connected, isFalse);
  });

  test('legacy sensor mapper accepts aliases', () {
    final result = mapRealtimeSensorData({
      'suhu': '26.5',
      'kelembapan': 70,
      'connected': true,
    });

    expect(result.temperature, 26.5);
    expect(result.humidity, 70);
    expect(result.connected, isTrue);
  });

  test('legacy sensor mapper returns empty data for invalid value', () {
    final result = mapRealtimeSensorData('invalid');

    expect(result.temperature, 0);
    expect(result.humidity, 0);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/realtime_monitoring_mapper_test.dart
```

Expected: FAIL because mapper file does not exist.

- [ ] **Step 3: Create historical entity**

Create `lib/features/history/domain/entities/historical_mcb_data.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

class HistoricalMcbData {
  final String id;
  final DateTime timestamp;
  final McbData? mcb1;
  final SensorData? sensorData;

  const HistoricalMcbData({
    required this.id,
    required this.timestamp,
    this.mcb1,
    this.sensorData,
  });

  @override
  String toString() {
    return 'HistoricalMcbData(id: $id, timestamp: $timestamp)';
  }
}
```

- [ ] **Step 4: Create realtime mapper**

Create `lib/features/monitoring/data/mappers/realtime_monitoring_mapper.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

McbDataCollection mapRealtimeMonitoringData(dynamic value) {
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

SensorData mapRealtimeSensorData(dynamic value) {
  if (value is! Map) return SensorData.empty();

  try {
    final map = Map<String, dynamic>.from(value);
    return SensorData(
      temperature: parseFirebaseDouble(
        map['temperature'] ?? map['temp'] ?? map['suhu'],
      ),
      humidity: parseFirebaseDouble(
        map['humidity'] ?? map['hum'] ?? map['kelembapan'],
      ),
      connected: map['connected'] == true,
    );
  } catch (_) {
    return SensorData.empty();
  }
}
```

- [ ] **Step 5: Update monitoring data source**

In `firebase_monitoring_data_source.dart`:

- remove direct entity imports;
- remove local `parseMonitoringData()` implementation;
- import `realtime_monitoring_mapper.dart`;
- keep temporary forwarding functions only if direct tests/callers still import them:

```dart
McbDataCollection parseMonitoringData(dynamic value) {
  return mapRealtimeMonitoringData(value);
}
```

- change `getSensorDataStream()` body to:

```dart
return database.child('device/sensorData/environment').onValue.map((event) {
  return mapRealtimeSensorData(event.snapshot.value);
});
```

- [ ] **Step 6: Run focused tests**

Run:

```powershell
flutter test test/realtime_monitoring_mapper_test.dart test/firebase_monitoring_data_source_test.dart
```

Expected: PASS.

### Task 3: Firestore History Mapper

**Files:**
- Create: `lib/features/history/data/mappers/firestore_history_mapper.dart`
- Modify: `lib/features/history/data/datasources/firebase_history_data_source.dart`
- Create: `test/firestore_history_mapper_test.dart`
- Modify: `test/firebase_history_data_source_test.dart`

**Consumes:** Historical/monitoring domain entities; `parseFirebaseDouble`; `Timestamp`; `DateFormat`.

**Produces:**

```dart
DateTime parseFirestoreTimestamp(dynamic timestamp);
HistoricalMcbData mapCanonicalFirestoreHistory(Map<String, dynamic> data, String id);
HistoricalMcbData mapLegacyFirestoreHistory(Map<String, dynamic> data, String id);
HistoricalMcbData createLegacyHistoricalMcbData(
  McbDataCollection collection,
  String id,
  DateTime timestamp,
);
Map<String, dynamic> mapLegacyHistoricalMcbDataToFirestore(
  HistoricalMcbData historicalData,
);
Map<String, dynamic> mapLegacyHistoricalMcbDataToMap(
  HistoricalMcbData historicalData,
);
```

- [ ] **Step 1: Write failing mapper tests**

Create `test/firestore_history_mapper_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/mappers/firestore_history_mapper.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical mapper retains sensorLogs schema and timestamp lastUpdate', () {
    final result = mapCanonicalFirestoreHistory({
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

    expect(result.id, 'canonical-1');
    expect(result.timestamp, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(result.mcb1!.lastUpdate, 1000);
    expect(result.sensorData!.humidity, 60);
  });

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

  test('legacy mapper retains nullable missing nodes', () {
    final result = mapLegacyFirestoreHistory({
      'timestamp': '2026-07-13T10:30:00.000',
    }, 'legacy-1');

    expect(result.mcb1, isNull);
    expect(result.sensorData, isNull);
  });

  test('legacy mapper reads mcb1 and dht schema', () {
    final result = mapLegacyFirestoreHistory({
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

    expect(result.mcb1!.lastUpdate, 7);
    expect(result.sensorData!.temperature, 26);
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

    final firestore = mapLegacyHistoricalMcbDataToFirestore(historical);
    final map = mapLegacyHistoricalMcbDataToMap(historical);

    expect(firestore['timestamp'], DateTime(2026, 7, 13, 10, 30));
    expect(map['timestamp'], '2026-07-13T10:30:00.000');
    expect(firestore['mcb1']['lastUpdate'], 7);
    expect(firestore['dht'], {'temperature': 26.0, 'humidity': 55.0});
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
flutter test test/firestore_history_mapper_test.dart
```

Expected: FAIL because mapper file does not exist.

- [ ] **Step 3: Create Firestore mapper**

Move existing `parseFirestoreTimestamp` logic from `firebase_history_data_source.dart:18-41` unchanged into mapper. Implement canonical mapper from current `parseHistoricalMcbData` behavior: missing `power` or `environment` uses an empty map; present non-`Map` node throws so data source logs and skips document. Implement legacy mapper and serializers from `lib/models/model.dart:206-283`, preserving catch fallback, nullable nodes, key names, and timestamp representation.

- [ ] **Step 4: Update history data source**

In `firebase_history_data_source.dart`:

- remove local `parseFirestoreTimestamp()` and `parseHistoricalMcbData()` implementation;
- import mapper and domain entities;
- retain forwarding functions only if existing direct tests rely on them:

```dart
HistoricalMcbData parseHistoricalMcbData(
  Map<String, dynamic> data,
  String id,
) {
  return mapCanonicalFirestoreHistory(data, id);
}
```

- replace legacy calls:

```dart
HistoricalMcbData.fromFirestore(...)              // mapLegacyFirestoreHistory(...)
HistoricalMcbData.fromMcbCollection(...)          // createLegacyHistoricalMcbData(...)
historicalData.toFirestore()                       // mapLegacyHistoricalMcbDataToFirestore(...)
```

Do not change collection, query, stream, ordering, limit, exception text, or safe method catches.

- [ ] **Step 5: Update history data source tests**

Change `test/firebase_history_data_source_test.dart` imports from data source parser to `firestore_history_mapper.dart` when testing mapper functions. Keep collection constant test in data source import if constants remain there.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
flutter test test/firestore_history_mapper_test.dart test/firebase_history_data_source_test.dart
```

Expected: PASS.

### Task 4: Migrate Imports and Delete Legacy Model

**Files:**
- Modify every current import of `package:esh/models/model.dart` in `lib/` and `test/`.
- Delete: `lib/models/model.dart`
- Modify: `test/architecture_boundary_test.dart`

**Consumes:** New entities and mappers from Tasks 1-3.

- [ ] **Step 1: Update monitoring imports**

Replace imports in following files with exact needed entity imports:

```text
lib/bloc/monitoring/monitoring_event.dart
lib/bloc/monitoring/monitoring_state.dart
lib/bloc/monitoring/monitoring_bloc.dart
lib/screen/monitoring.dart
lib/features/monitoring/domain/repositories/monitoring_repository.dart
lib/features/monitoring/data/repositories/monitoring_repository_impl.dart
test/monitoring_bloc_test.dart
test/app_dependencies_test.dart
test/repository_implementation_test.dart
```

Use:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
```

Only import each type used by file.

- [ ] **Step 2: Update history imports**

Replace imports in:

```text
lib/bloc/history/history_state.dart
lib/bloc/history/history_bloc.dart
lib/features/history/domain/repositories/history_repository.dart
lib/features/history/data/repositories/history_repository_impl.dart
lib/features/history/data/datasources/firebase_history_data_source.dart
test/app_dependencies_test.dart
test/repository_implementation_test.dart
```

Use:

```dart
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
```

Only import each type used by file.

- [ ] **Step 3: Add failing legacy-model boundary test**

Add to `test/architecture_boundary_test.dart`:

```dart
test('legacy mixed model file is removed', () {
  expect(File('lib/models/model.dart').existsSync(), isFalse);
});

test('domain entities avoid data and framework types', () {
  const entityFiles = [
    'lib/features/monitoring/domain/entities/sensor_data.dart',
    'lib/features/monitoring/domain/entities/mcb_data.dart',
    'lib/features/monitoring/domain/entities/mcb_data_collection.dart',
    'lib/features/history/domain/entities/historical_mcb_data.dart',
  ];
  const forbiddenTokens = [
    'Map<',
    'dynamic',
    'fromMap',
    'toMap',
    'fromFirestore',
    'toFirestore',
    'package:firebase_',
    'package:cloud_firestore/',
    'package:flutter/',
    '/data/',
  ];

  for (final file in entityFiles) {
    final source = readProjectFile(file);
    for (final forbiddenToken in forbiddenTokens) {
      expect(source, isNot(contains(forbiddenToken)), reason: file);
    }
  }
});
```

- [ ] **Step 4: Run boundary test to verify failure**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: FAIL because `lib/models/model.dart` still exists.

- [ ] **Step 5: Confirm no legacy imports remain**

Run:

```powershell
rg "models/model\.dart" lib test
```

Expected: no match.

- [ ] **Step 6: Delete legacy model**

Verify target:

```powershell
Test-Path -LiteralPath "lib\models\model.dart"
```

Expected: `True`.

Delete only file:

```powershell
Remove-Item -LiteralPath "lib\models\model.dart"
```

- [ ] **Step 7: Run migration-focused tests**

Run:

```powershell
flutter test test/domain_entities_test.dart test/realtime_monitoring_mapper_test.dart test/firestore_history_mapper_test.dart test/architecture_boundary_test.dart test/monitoring_bloc_test.dart test/repository_implementation_test.dart test/firebase_monitoring_data_source_test.dart test/firebase_history_data_source_test.dart
```

Expected: PASS.

### Task 5: Full Verification

**Files:**
- Modify only planned Dart/test files when formatter requires it.

- [ ] **Step 1: Format changed scope**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
```

Expected: exit `0`.

If formatter flags unrelated `lib/firebase_options.dart`, leave file unchanged. Format only changed Stage 3 Dart/test files, then rerun check for changed scope.

- [ ] **Step 2: Static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 3: Run full test suite**

Run:

```powershell
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Build Android debug APK**

Run:

```powershell
flutter build apk --debug
```

Expected: `build\app\outputs\flutter-apk\app-debug.apk` exists.

- [ ] **Step 5: Final boundary and scope audit**

Run:

```powershell
rg "models/model\.dart" lib test
rg "fromMap|toMap|fromFirestore|toFirestore" lib/features/*/domain/entities
git diff --check
git status --short
git diff --stat
```

Expected: no legacy model import; no mapper/serialization method in entity; no whitespace error; only stage 1-3 intended changes.

- [ ] **Step 6: Do not commit**

User has not requested a commit. Leave changes unstaged.

## Self-Review

- Spec coverage: entity purity, realtime parser aliases/null/malformed root, canonical/legacy Firestore mapping, serialization, import migration, old-model deletion, boundary enforcement, and verification included.
- Placeholder scan: none.
- Type consistency: entity names, mapper signatures, legacy schema names, and importer paths match approved spec.
- Scope boundary: no DTO redesign, use case, typed device state, Firebase path/query/payload change, UI visual change, or `DeviceConfig` migration.
