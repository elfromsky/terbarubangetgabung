# Clean Architecture Data Model DTO Step 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lengkapi Step 4 dengan DTO internal untuk Realtime, `sensorLogs`, dan `energyData`; data source hasilkan DTO, repository map DTO ke entity domain.

**Architecture:** DTO menangani raw Firebase schema dan serialisasi tanpa import domain entity. Mapper raw-ke-DTO dan DTO-ke-entity memisahkan Firebase representation dari domain. Repository implementation menjadi satu-satunya boundary yang menerjemahkan data DTO menjadi entity contract. BLoC/UI tetap memakai entity dan tidak berubah.

**Tech Stack:** Flutter, Dart 3.8.1, firebase_database 10.5.0, cloud_firestore 4.15.0, intl 0.20.2, flutter_test.

## Global Constraints

- Jangan ubah Firebase path, collection, query boundary, ordering, limit, payload command, BLoC, state, route, atau UI.
- Pertahankan telemetry malformed/default behavior, sensor alias, timestamp fallback, canonical malformed-node skip, legacy nullability, legacy safe empty-list, dan legacy serialization.
- Tidak ada caller luar package untuk public data source; data source interface boleh berubah internal ke DTO.
- DTO tidak import domain entity, Flutter, BLoC, UI, repository contract, atau Firebase SDK.
- Entity tidak import data/DTO/mapper/Firebase/Flutter atau mengandung Map/dynamic/serialization.
- Repository contract tetap expose entity; repository implementation tidak import Firebase SDK.
- Jangan tambah dependency atau commit.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/features/monitoring/data/models/realtime_monitoring_dto.dart` | Raw normalized environment/power telemetry. |
| `lib/features/monitoring/data/models/sensor_data_dto.dart` | Raw alias-normalized sensor payload. |
| `lib/features/history/data/models/canonical_history_dto.dart` | Raw canonical `sensorLogs` record. |
| `lib/features/history/data/models/legacy_history_dto.dart` | Raw legacy `energyData` record plus map serialization. |
| `lib/features/monitoring/data/mappers/realtime_monitoring_mapper.dart` | Raw Firebase to monitoring DTO. |
| `lib/features/monitoring/data/mappers/monitoring_entity_mapper.dart` | Monitoring DTO to domain entity. |
| `lib/features/history/data/mappers/firestore_history_mapper.dart` | Firestore map to history DTO. |
| `lib/features/history/data/mappers/history_entity_mapper.dart` | History DTO to/from domain entity. |
| `lib/features/*/data/datasources/*.dart` | Firebase SDK calls and DTO production only. |
| `lib/features/*/data/repositories/*.dart` | DTO to entity mapping and domain contracts. |

### Task 1: Monitoring DTO and Entity Mapper

**Files:**
- Create: `lib/features/monitoring/data/models/realtime_monitoring_dto.dart`
- Create: `lib/features/monitoring/data/models/sensor_data_dto.dart`
- Create: `lib/features/monitoring/data/mappers/monitoring_entity_mapper.dart`
- Modify: `lib/features/monitoring/data/mappers/realtime_monitoring_mapper.dart`
- Test: `test/monitoring_dto_test.dart`

**Interfaces:**

```dart
class RealtimeMonitoringDto {
  final Map<String, dynamic> environment;
  final Map<String, dynamic> power;

  const RealtimeMonitoringDto({
    required this.environment,
    required this.power,
  });

  factory RealtimeMonitoringDto.empty();
}

class SensorDataDto {
  final dynamic temperature;
  final dynamic humidity;
  final bool connected;

  const SensorDataDto({
    required this.temperature,
    required this.humidity,
    required this.connected,
  });

  factory SensorDataDto.empty();
}

McbDataCollection mapRealtimeMonitoringDtoToEntity(
  RealtimeMonitoringDto dto,
);
SensorData mapSensorDataDtoToEntity(SensorDataDto dto);
```

- [ ] **Step 1: Write failing DTO tests**

Create `test/monitoring_dto_test.dart`:

```dart
import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime DTO normalizes nested Firebase map without parsing numbers', () {
    final dto = mapRealtimeMonitoringDataToDto({
      'environment': {'temperature': '28.5', 'humidity': 60},
      'power': {'voltage': '220', 'energy': 12.5},
    });

    expect(dto.environment['temperature'], '28.5');
    expect(dto.power['voltage'], '220');
    expect(dto.power['energy'], 12.5);
  });

  test('realtime DTO empty fallback maps to empty entity', () {
    final dto = mapRealtimeMonitoringDataToDto('invalid');
    final entity = mapRealtimeMonitoringDtoToEntity(dto);

    expect(entity.mcb1.energy, 0);
    expect(entity.sensorData.temperature, 0);
  });

  test('sensor DTO supports aliases and entity mapper normalizes invalid number', () {
    final dto = mapRealtimeSensorDataToDto({
      'suhu': '26.5',
      'kelembapan': 'invalid',
      'connected': true,
    });
    final entity = mapSensorDataDtoToEntity(dto);

    expect(entity.temperature, 26.5);
    expect(entity.humidity, 0);
    expect(entity.connected, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/monitoring_dto_test.dart
```

Expected: FAIL because DTO/entity mapper APIs do not exist.

- [ ] **Step 3: Create DTO files**

Create `realtime_monitoring_dto.dart`:

```dart
class RealtimeMonitoringDto {
  final Map<String, dynamic> environment;
  final Map<String, dynamic> power;

  const RealtimeMonitoringDto({
    required this.environment,
    required this.power,
  });

  factory RealtimeMonitoringDto.empty() {
    return const RealtimeMonitoringDto(environment: {}, power: {});
  }
}
```

Create `sensor_data_dto.dart`:

```dart
class SensorDataDto {
  final dynamic temperature;
  final dynamic humidity;
  final bool connected;

  const SensorDataDto({
    required this.temperature,
    required this.humidity,
    required this.connected,
  });

  factory SensorDataDto.empty() {
    return const SensorDataDto(
      temperature: null,
      humidity: null,
      connected: false,
    );
  }
}
```

- [ ] **Step 4: Update raw-to-DTO mapper**

Replace entity imports and functions in `realtime_monitoring_mapper.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/sensor_data_dto.dart';

RealtimeMonitoringDto mapRealtimeMonitoringDataToDto(dynamic value) {
  if (value is! Map) return RealtimeMonitoringDto.empty();

  final root = normalizeFirebaseMap(value);
  final environment = root['environment'];
  final power = root['power'];
  return RealtimeMonitoringDto(
    environment: environment is Map
        ? normalizeFirebaseMap(environment)
        : <String, dynamic>{},
    power: power is Map ? normalizeFirebaseMap(power) : <String, dynamic>{},
  );
}

SensorDataDto mapRealtimeSensorDataToDto(dynamic value) {
  if (value is! Map) return SensorDataDto.empty();
  try {
    final map = Map<String, dynamic>.from(value);
    return SensorDataDto(
      temperature: map['temperature'] ?? map['temp'] ?? map['suhu'],
      humidity: map['humidity'] ?? map['hum'] ?? map['kelembapan'],
      connected: map['connected'] == true,
    );
  } catch (_) {
    return SensorDataDto.empty();
  }
}
```

- [ ] **Step 5: Create DTO-to-entity mapper**

Create `monitoring_entity_mapper.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/sensor_data_dto.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

McbDataCollection mapRealtimeMonitoringDtoToEntity(
  RealtimeMonitoringDto dto,
) {
  return McbDataCollection(
    mcb1: McbData(
      connected: dto.power['connected'] == true,
      voltage: parseFirebaseDouble(dto.power['voltage']),
      current: parseFirebaseDouble(dto.power['current']),
      power: parseFirebaseDouble(dto.power['power']),
      energy: parseFirebaseDouble(dto.power['energy']),
    ),
    sensorData: SensorData(
      temperature: parseFirebaseDouble(dto.environment['temperature']),
      humidity: parseFirebaseDouble(dto.environment['humidity']),
      connected: dto.environment['connected'] == true,
    ),
  );
}

SensorData mapSensorDataDtoToEntity(SensorDataDto dto) {
  return SensorData(
    temperature: parseFirebaseDouble(dto.temperature),
    humidity: parseFirebaseDouble(dto.humidity),
    connected: dto.connected,
  );
}
```

- [ ] **Step 6: Run focused test**

Run:

```powershell
flutter test test/monitoring_dto_test.dart
```

Expected: PASS.

### Task 2: History DTO and Entity Mapper

**Files:**
- Create: `lib/features/history/data/models/canonical_history_dto.dart`
- Create: `lib/features/history/data/models/legacy_history_dto.dart`
- Create: `lib/features/history/data/mappers/history_entity_mapper.dart`
- Modify: `lib/features/history/data/mappers/firestore_history_mapper.dart`
- Test: `test/history_dto_test.dart`

**Interfaces:**

```dart
class CanonicalHistoryDto {
  final String id;
  final dynamic timestamp;
  final Map<String, dynamic> power;
  final Map<String, dynamic> environment;
}

class LegacyHistoryDto {
  final String id;
  final dynamic timestamp;
  final dynamic mcb1;
  final dynamic dht;

  Map<String, dynamic> toMap();
}

CanonicalHistoryDto mapFirestoreToCanonicalHistoryDto(
  Map<String, dynamic> data,
  String id,
);
LegacyHistoryDto mapFirestoreToLegacyHistoryDto(
  Map<String, dynamic> data,
  String id,
);
HistoricalMcbData mapCanonicalHistoryDtoToEntity(CanonicalHistoryDto dto);
HistoricalMcbData mapLegacyHistoryDtoToEntity(LegacyHistoryDto dto);
LegacyHistoryDto mapLegacyHistoricalEntityToDto(
  HistoricalMcbData entity,
  {required bool timestampAsIsoString},
);
```

- [ ] **Step 1: Write failing DTO tests**

Create `test/history_dto_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/mappers/firestore_history_mapper.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical DTO retains raw timestamp and schema maps', () {
    final dto = mapFirestoreToCanonicalHistoryDto({
      'timestamp': Timestamp(1, 0),
      'power': {'energy': '4.25'},
      'environment': {'humidity': 60},
    }, 'canonical');

    expect(dto.timestamp, Timestamp(1, 0));
    expect(dto.power['energy'], '4.25');
    expect(dto.environment['humidity'], 60);
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
    const entity = HistoricalMcbData(
      id: 'legacy',
      timestamp: DateTime(2026, 7, 13, 10, 30),
      mcb1: McbData(
        connected: true,
        voltage: 220,
        current: 1.5,
        power: 330,
        energy: 2.5,
        lastUpdate: 7,
      ),
      sensorData: SensorData(temperature: 26, humidity: 55),
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
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/history_dto_test.dart
```

Expected: FAIL because DTO APIs do not exist.

- [ ] **Step 3: Create history DTO files**

`canonical_history_dto.dart`:

```dart
class CanonicalHistoryDto {
  final String id;
  final dynamic timestamp;
  final Map<String, dynamic> power;
  final Map<String, dynamic> environment;

  const CanonicalHistoryDto({
    required this.id,
    required this.timestamp,
    required this.power,
    required this.environment,
  });
}
```

`legacy_history_dto.dart`:

```dart
class LegacyHistoryDto {
  final String id;
  final dynamic timestamp;
  final dynamic mcb1;
  final dynamic dht;

  const LegacyHistoryDto({
    required this.id,
    required this.timestamp,
    this.mcb1,
    this.dht,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'mcb1': mcb1,
      if (dht != null) 'dht': dht,
    };
  }
}
```

- [ ] **Step 4: Replace raw-to-entity Firestore mapper**

`firestore_history_mapper.dart` keeps only raw data to DTO factories:

```dart
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
```

Keep casts exact so present non-`Map` canonical nodes throw and source skips doc.

- [ ] **Step 5: Create history entity mapper**

Move timestamp parsing, canonical entity construction, legacy try/catch fallback, legacy MCB/sensor parsing, legacy entity-to-DTO serialization from old Firestore mapper into `history_entity_mapper.dart`. Imports may include data DTOs, data numeric utility, Firebase `Timestamp`, `intl`, and domain entities. Keep all function behavior exact.

- [ ] **Step 6: Run focused test**

Run:

```powershell
flutter test test/history_dto_test.dart test/firestore_history_mapper_test.dart
```

Expected: PASS.

### Task 3: DTO Data Sources and Repository Entity Boundaries

**Files:**
- Modify: `lib/features/monitoring/data/datasources/firebase_monitoring_data_source.dart`
- Modify: `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart`
- Modify: `lib/features/history/data/datasources/firebase_history_data_source.dart`
- Modify: `lib/features/history/data/repositories/history_repository_impl.dart`
- Modify: `test/repository_implementation_test.dart`

- [ ] **Step 1: Write failing repository conversion tests**

Extend `test/repository_implementation_test.dart` with fake data sources returning DTO. Assert repository emits entity field values from DTO streams and maps history DTO result list into `HistoricalMcbData` with correct timestamp/metrics.

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/repository_implementation_test.dart
```

Expected: FAIL because data source interfaces still return entities.

- [ ] **Step 3: Change monitoring data source interface and implementation**

```dart
abstract interface class MonitoringDataSource {
  Stream<RealtimeMonitoringDto> getMonitoringDataStream();
  Stream<bool> getConnectionStatus();
}
```

`FirebaseMonitoringDataSource.getMonitoringDataStream()` maps Firebase event value via `mapRealtimeMonitoringDataToDto`. `getSensorDataStream()` returns `Stream<SensorDataDto>` via `mapRealtimeSensorDataToDto`. Remove domain entity imports and legacy public entity forwarding parser from data source.

- [ ] **Step 4: Map monitoring DTO at repository**

```dart
@override
Stream<McbDataCollection> getMonitoringDataStream() {
  return monitoringDataSource
      .getMonitoringDataStream()
      .map(mapRealtimeMonitoringDtoToEntity);
}
```

Keep room stream, connection stream, command unchanged.

- [ ] **Step 5: Change history data source interface and implementation**

```dart
abstract interface class HistoryDataSource {
  Future<List<CanonicalHistoryDto>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}
```

Canonical query maps `doc.data()` via `mapFirestoreToCanonicalHistoryDto`, logs/skips factory error. Legacy methods return `List<LegacyHistoryDto>`. `saveHistoricalData` accepts `LegacyHistoryDto` then writes `dto.toMap()`.

- [ ] **Step 6: Map history DTO at repository**

```dart
@override
Future<List<HistoricalMcbData>> getHistoricalData({
  required DateTime startDate,
  required DateTime endDate,
  int limit = 1000,
}) async {
  final data = await historyDataSource.getHistoricalData(
    startDate: startDate,
    endDate: endDate,
    limit: limit,
  );
  return data.map(mapCanonicalHistoryDtoToEntity).toList();
}
```

- [ ] **Step 7: Run repository and integration tests**

Run:

```powershell
flutter test test/repository_implementation_test.dart test/monitoring_bloc_test.dart test/app_dependencies_test.dart test/firebase_monitoring_data_source_test.dart test/firebase_history_data_source_test.dart
```

Expected: PASS after converting fakes to DTO types.

### Task 4: Boundary Tests and Final API Cleanup

**Files:**
- Modify: `test/architecture_boundary_test.dart`
- Modify: mapper/data source tests that import removed forwarding API.

- [ ] **Step 1: Add failing DTO boundary tests**

Add tests asserting:

- monitoring/history data source source contains DTO return types;
- both repository contracts contain entity return types and no `Dto`;
- DTO files avoid `package:flutter`, `flutter_bloc`, `domain/entities`, `domain/repositories`, and Firebase SDK imports;
- repository implementation contains DTO-to-entity mapper invocation.

- [ ] **Step 2: Run boundary test to verify failure**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: FAIL until Task 3 complete.

- [ ] **Step 3: Migrate/replace old mapper forwarding tests**

Move direct entity parser expectations from `firebase_monitoring_data_source_test.dart` and `firebase_history_data_source_test.dart` to DTO/mapper tests. Keep tests for data source collection constants only. No source should reference removed `parseMonitoringData`, `parseHistoricalMcbData`, `mapRealtimeMonitoringData`, or `mapCanonicalFirestoreHistory` entity-return APIs.

- [ ] **Step 4: Verify forbidden boundary leaks**

Run available content search for:

```text
getMonitoringDataStream() returns entity in data source
getHistoricalData() returns entity in data source
package:esh/features/*/domain/entities in data/models
Dto in domain/repositories
```

Expected: no forbidden leak. Entity imports only data mapper/repository/data source legacy method parameter where spec permits.

- [ ] **Step 5: Run focused boundary tests**

Run:

```powershell
flutter test test/architecture_boundary_test.dart test/monitoring_dto_test.dart test/history_dto_test.dart
```

Expected: PASS.

### Task 5: Full Verification

- [ ] **Step 1: Format changed scope**

Run global check:

```powershell
dart format --output=none --set-exit-if-changed lib test
```

If only `lib/firebase_options.dart` flags, leave it unchanged. Format planned Step 4 files only, then rerun changed-scope check.

- [ ] **Step 2: Run static analysis**

```powershell
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 3: Run full tests**

```powershell
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Build debug APK**

```powershell
flutter build apk --debug
```

Expected: `build\app\outputs\flutter-apk\app-debug.apk` exists.

- [ ] **Step 5: Scope audit**

```powershell
git diff --check
git status --short
git diff --stat
```

Expected: no whitespace errors; Stage 1-4 planned changes only; no commit.

## Self-Review

- Coverage: all schema DTO, raw/DTO/entity conversion, data source/repository boundary, legacy serialization, unchanged Firebase behavior, and tests included.
- Type consistency: all DTO/entity mapper names and contract return types match every task.
- Scope: no UI, BLoC, route, query/payload, use case, typed device state, or external adapter changes.
- Contradiction scan: DTO never imports entity; entity-to-DTO conversion lives history entity mapper; data source uses DTO, repository maps DTO to entity.
