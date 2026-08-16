# Typed Device State Plan 7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ganti raw Firebase room-state map dengan typed `DeviceAddress`, `RoomDeviceValue`, dan `RoomDeviceCollection`, lalu tampilkan `unknown`, `off`, `on`, `pending`, dan `failed` dengan perilaku semantik yang berbeda tanpa redesign visual besar.

**Architecture:** Firebase data source hanya mengeluarkan DTO data-layer. Mapper room-device menjadi satu-satunya parser bentuk node Firebase dan mengubah DTO menjadi entity domain immutable. Repository, use case, BLoC, presentation mapper, dan screen hanya memakai typed collection; BLoC mempertahankan confirmed snapshot, optimistic visible snapshot, pending address, dan error per device secara terpisah.

**Tech Stack:** Flutter, Dart 3.8.1, flutter_bloc 9.1.1, firebase_database 10.5.0, flutter_test, Material icons, existing app theme.

## Global Constraints

- Pertahankan route `/`, `/control`, `/history`.
- Pertahankan dark olive-to-yellow gradient, translucent cards, Material icons, typography, spacing, radius, button labels, dan layout hierarchy yang ada.
- Pertahankan Firebase room path `rooms`, command path `commands/rooms/$roomKey/$deviceKey`, command payload, timeout 5 detik, rollback, dan confirmation semantics.
- Jangan ubah Firebase schema, query telemetry, command payload, firmware contract, hardware behavior, history flow, cost/emission calculation, atau Plan 9 logic.
- Jangan menggabungkan `kamar_1/lampu` dan `kamar_2/lampu`; alamat selalu pasangan `roomKey` dan `deviceKey`.
- Jangan menambah dependency, animation library, state-management library, global theme, fixed overlay, polling, network call, atau stream baru.
- Raw `Map<String, dynamic>` room state boleh berada di DTO/mapper/data source, tetapi tidak boleh keluar dari data layer menuju repository contract, use case, BLoC, event, state, presentation mapper, atau screen.
- Hanya mapper room-device yang membaca node keys `state` dan `brightness`; data source tetap memiliki literal Firebase path `rooms` karena path harus identik.
- Missing atau malformed device tidak boleh dibuat menjadi OFF.
- Pending hanya men-disable control untuk `DeviceAddress` terkait; command device lain tetap bisa diproses.
- Failed mempertahankan error dan confirmed value bila tersedia. Jika confirmed value tidak tersedia, status failed tetap terlihat tetapi control disabled.
- Status tidak boleh mengandalkan warna saja. Label, icon, semantic text, dan control availability wajib ikut membedakan state.
- Pertahankan no-horizontal-overflow pada lebar `320` dengan text scale `2x`.
- Pertahankan minimum touch target Android `48x48dp` bila memungkinkan dengan existing Material controls.
- Jangan mengubah file Dart sekarang selama penulisan plan. Implementer harus mendapat approval terpisah sebelum eksekusi.
- Jangan commit, amend, push, atau mengubah file kerja lain tanpa permintaan eksplisit.
- Worktree sudah memiliki perubahan dari Plan 1-6. Jangan reset, checkout, atau overwrite perubahan unrelated.

---

## Existing Context

Current typed telemetry migration sudah tersedia di:

- `lib/features/monitoring/domain/entities/mcb_data.dart`
- `lib/features/monitoring/domain/entities/mcb_data_collection.dart`
- `lib/features/monitoring/data/models/realtime_monitoring_dto.dart`
- `lib/features/monitoring/data/mappers/monitoring_entity_mapper.dart`
- `lib/features/monitoring/data/datasources/firebase_monitoring_data_source.dart`
- `lib/features/monitoring/domain/repositories/monitoring_repository.dart`
- `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart`
- `lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart`
- `lib/bloc/monitoring/monitoring_bloc.dart`
- `lib/bloc/monitoring/monitoring_state.dart`
- `lib/bloc/monitoring/monitoring_event.dart`

Current room-device pipeline masih raw:

```text
FirebaseRoomDeviceDataSource
  -> Stream<Map<String, dynamic>>
  -> MonitoringRepositoryImpl
  -> WatchRoomDevicesUseCase
  -> DeviceStateUpdated(Map<String, dynamic>)
  -> MonitoringLoaded.deviceData / confirmedDeviceData
  -> monitoring.dart / control.dart membaca rooms/state/brightness
```

Current BLoC memakai key gabungan string `roomKey/deviceKey`, optimistic map copy, dan helper parser map di `lib/bloc/monitoring/monitoring_bloc.dart`. Current screen memakai fallback malformed/missing menjadi `false`, sehingga unknown terlihat OFF. Plan ini mengganti seluruh jalur tersebut dengan typed flow.

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/features/monitoring/domain/entities/room_device_state.dart` | `DeviceAddress` dan `RoomDeviceValue`, value semantics tanpa Flutter/Firebase. |
| `lib/features/monitoring/domain/entities/room_device_collection.dart` | Immutable lookup/set collection keyed by `DeviceAddress`. |
| `lib/features/monitoring/data/models/room_device_collection_dto.dart` | DTO yang membungkus raw `/rooms` snapshot hanya di data layer. |
| `lib/features/monitoring/data/mappers/room_device_mapper.dart` | Parse raw Firebase room snapshot, validate node shape, normalize brightness, dan map ke domain. |
| `lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart` | Return DTO dari `/rooms`; command path/payload tetap unchanged. |
| `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart` | Map DTO stream menjadi `RoomDeviceCollection`. |
| `lib/features/monitoring/domain/repositories/monitoring_repository.dart` | Expose typed room collection contract. |
| `lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart` | Expose typed room collection stream. |
| `lib/bloc/monitoring/monitoring_event.dart` | Typed device update, pending-clear, dan command-failure events. |
| `lib/bloc/monitoring/monitoring_state.dart` | Typed visible/confirmed snapshots dan per-device command state. |
| `lib/bloc/monitoring/monitoring_bloc.dart` | Typed optimistic, confirmation, concurrent pending, timeout, dan rollback transitions. |
| `lib/features/monitoring/presentation/models/device_control_view_state.dart` | Presentation phase enum dan derived view state. |
| `lib/features/monitoring/presentation/mappers/device_control_view_mapper.dart` | Convert typed state + pending/error menjadi UI phase. |
| `lib/screen/monitoring.dart` | Render typed electronic status tanpa Firebase key parsing. |
| `lib/screen/control.dart` | Render typed hardware status dan typed control availability. |
| `test/domain_entities_test.dart` | Entity equality, normalization contract, collection immutability. |
| `test/room_device_mapper_test.dart` | Raw Firebase room node mapping dan malformed-node behavior. |
| `test/firebase_room_device_data_source_test.dart` | Existing command path/payload regression dan DTO boundary. |
| `test/repository_implementation_test.dart` | Typed room stream mapping regression. |
| `test/use_case_test.dart` | Typed room stream delegation regression. |
| `test/monitoring_bloc_test.dart` | Typed BLoC transition and concurrent command tests. |
| `test/device_control_view_mapper_test.dart` | Phase priority and control availability tests. |
| `test/monitoring_device_widget_test.dart` | Status label/icon/brightness and responsive control tests. |
| `test/architecture_boundary_test.dart` | Raw map boundary and import/key-parsing enforcement. |

`lib/app/app_dependencies.dart`, `lib/main.dart`, `lib/routes/router.dart`, `lib/widgets/appbar.dart`, `lib/widgets/selector_page.dart`, history files, telemetry DTOs, dan cost/emission code tidak perlu behavior change. `AppDependencies` tetap menyusun dependency yang sama; perubahan return type room stream mengalir melalui compiler.

---

### Task 1: Domain Room Device Entities

**Files:**
- Create: `lib/features/monitoring/domain/entities/room_device_state.dart`
- Create: `lib/features/monitoring/domain/entities/room_device_collection.dart`
- Modify: `test/domain_entities_test.dart`
- Modify: `test/architecture_boundary_test.dart`

**Interfaces:**

```dart
class DeviceAddress {
  final String roomKey;
  final String deviceKey;

  const DeviceAddress({
    required this.roomKey,
    required this.deviceKey,
  });

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

class RoomDeviceValue {
  final bool isOn;
  final int? brightness;

  const RoomDeviceValue({
    required this.isOn,
    this.brightness,
  });

  bool get isDimmable => brightness != null;
}

class RoomDeviceCollection {
  final Map<DeviceAddress, RoomDeviceValue> values;

  RoomDeviceCollection({required Map<DeviceAddress, RoomDeviceValue> values});

  factory RoomDeviceCollection.empty();

  RoomDeviceValue? find(DeviceAddress address);

  RoomDeviceCollection set(DeviceAddress address, RoomDeviceValue value);
}
```

- [ ] **Step 1: Add failing domain entity tests**

Tambahkan ke `test/domain_entities_test.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
```

Tambahkan test berikut:

```dart
test('DeviceAddress uses room and device keys for equality', () {
  const first = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
  const second = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
  const otherRoom = DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu');

  expect(first, second);
  expect(first.hashCode, second.hashCode);
  expect(first, isNot(otherRoom));
});

test('RoomDeviceValue distinguishes state-only and dimmable values', () {
  const stateOnly = RoomDeviceValue(isOn: true);
  const dimmable = RoomDeviceValue(isOn: true, brightness: 75);
  const dimmableOff = RoomDeviceValue(isOn: false, brightness: 0);

  expect(stateOnly.isDimmable, isFalse);
  expect(dimmable.isDimmable, isTrue);
  expect(dimmableOff.isDimmable, isTrue);
  expect(dimmableOff.brightness, 0);
  expect(stateOnly, isNot(dimmable));
});

test('RoomDeviceCollection lookup and set preserve immutable snapshots', () {
  const address = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
  const value = RoomDeviceValue(isOn: true);
  final empty = RoomDeviceCollection.empty();
  final updated = empty.set(address, value);

  expect(empty.find(address), isNull);
  expect(updated.find(address), value);
  expect(empty.values, isEmpty);
  expect(updated.values.length, 1);
  expect(updated.values[address], value);

  expect(
    () => updated.values[address] = const RoomDeviceValue(isOn: false),
    throwsUnsupportedError,
  );
});

test('missing device lookup remains unknown instead of off', () {
  const address = DeviceAddress(roomKey: 'teras', deviceKey: 'missing');
  expect(RoomDeviceCollection.empty().find(address), isNull);
});
```

- [ ] **Step 2: Run focused tests to verify failure**

Run:

```powershell
flutter test test/domain_entities_test.dart
```

Expected: FAIL because `room_device_state.dart` and `room_device_collection.dart` do not exist.

- [ ] **Step 3: Implement `DeviceAddress` and `RoomDeviceValue`**

Create `lib/features/monitoring/domain/entities/room_device_state.dart`:

```dart
class DeviceAddress {
  final String roomKey;
  final String deviceKey;

  const DeviceAddress({
    required this.roomKey,
    required this.deviceKey,
  });

  @override
  bool operator ==(Object other) {
    return other is DeviceAddress &&
        other.roomKey == roomKey &&
        other.deviceKey == deviceKey;
  }

  @override
  int get hashCode => Object.hash(roomKey, deviceKey);
}

class RoomDeviceValue {
  final bool isOn;
  final int? brightness;

  const RoomDeviceValue({
    required this.isOn,
    this.brightness,
  });

  bool get isDimmable => brightness != null;

  @override
  bool operator ==(Object other) {
    return other is RoomDeviceValue &&
        other.isOn == isOn &&
        other.brightness == brightness;
  }

  @override
  int get hashCode => Object.hash(isOn, brightness);
}
```

- [ ] **Step 4: Implement immutable `RoomDeviceCollection`**

Create `lib/features/monitoring/domain/entities/room_device_collection.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

class RoomDeviceCollection {
  final Map<DeviceAddress, RoomDeviceValue> values;

  RoomDeviceCollection({required Map<DeviceAddress, RoomDeviceValue> values})
    : values = Map<DeviceAddress, RoomDeviceValue>.unmodifiable(values);

  factory RoomDeviceCollection.empty() {
    return RoomDeviceCollection(values: const {});
  }

  RoomDeviceValue? find(DeviceAddress address) {
    return values[address];
  }

  RoomDeviceCollection set(DeviceAddress address, RoomDeviceValue value) {
    final next = Map<DeviceAddress, RoomDeviceValue>.from(values)
      ..[address] = value;
    return RoomDeviceCollection(values: next);
  }
}
```

- [ ] **Step 5: Run domain tests**

Run:

```powershell
flutter test test/domain_entities_test.dart
```

Expected: PASS, including equality, state-only/dimmable distinction, `brightness == 0`, missing lookup, and immutable map rejection.

- [ ] **Step 6: Add domain boundary assertions**

Tambahkan entity paths baru ke `test/architecture_boundary_test.dart`:

```dart
'lib/features/monitoring/domain/entities/room_device_state.dart',
'lib/features/monitoring/domain/entities/room_device_collection.dart',
```

Gunakan forbidden tokens berikut untuk kedua file baru:

```dart
const forbiddenTokens = [
  'package:flutter',
  'package:flutter_bloc',
  'package:firebase_',
  'package:cloud_firestore/',
  '/data/',
];
```

- [ ] **Step 7: Run boundary test**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: PASS untuk entity boundary dan existing architecture checks.

---

### Task 2: Room Device DTO and Firebase Mapper

**Files:**
- Create: `lib/features/monitoring/data/models/room_device_collection_dto.dart`
- Create: `lib/features/monitoring/data/mappers/room_device_mapper.dart`
- Modify: `lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart`
- Modify: `test/room_device_mapper_test.dart`
- Modify: `test/firebase_room_device_data_source_test.dart`

**Interfaces:**

```dart
class RoomDeviceCollectionDto {
  final Object? rawValue;

  const RoomDeviceCollectionDto({required this.rawValue});
}

RoomDeviceCollection mapRoomDeviceCollectionDtoToEntity(
  RoomDeviceCollectionDto dto,
);
```

`rawValue` hanya boleh dipakai dalam data model/mapper/data source. Tidak boleh muncul pada repository, use case, BLoC, atau UI.

- [ ] **Step 1: Add failing mapper tests**

Create `test/room_device_mapper_test.dart`:

```dart
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

  test('state-only bool nodes map to typed on and off values', () {
    final result = mapRoomDeviceCollectionDtoToEntity(
      const RoomDeviceCollectionDto(
        rawValue: {
          'teras': {'lampu': true, 'sanyo': false},
        },
      ),
    );

    expect(
      result.find(const DeviceAddress(roomKey: 'teras', deviceKey: 'lampu')),
      const RoomDeviceValue(isOn: true),
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'teras', deviceKey: 'sanyo')),
      const RoomDeviceValue(isOn: false),
    );
  });

  test('dimmable nodes preserve brightness including zero when off', () {
    final result = mapRoomDeviceCollectionDtoToEntity(
      const RoomDeviceCollectionDto(
        rawValue: {
          'kamar_1': {
            'lampu': {'state': false, 'brightness': 0},
          },
        },
      ),
    );

    expect(
      result.find(const DeviceAddress(roomKey: 'kamar_1', deviceKey: 'lampu')),
      const RoomDeviceValue(isOn: false, brightness: 0),
    );
  });

  test('integer double and string brightness values become clamped integers', () {
    final result = mapRoomDeviceCollectionDtoToEntity(
      const RoomDeviceCollectionDto(
        rawValue: {
          'dapur': {
            'int': {'state': true, 'brightness': 40},
            'double': {'state': true, 'brightness': 50.9},
            'string': {'state': true, 'brightness': '75'},
            'high': {'state': true, 'brightness': 125},
            'low': {'state': false, 'brightness': -5},
          },
        },
      ),
    );

    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'int'))?.brightness,
      40,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'double'))?.brightness,
      50,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'string'))?.brightness,
      75,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'high'))?.brightness,
      100,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'low'))?.brightness,
      0,
    );
  });

  test('malformed rooms and device nodes are ignored without inventing off', () {
    final result = mapRoomDeviceCollectionDtoToEntity(
      const RoomDeviceCollectionDto(
        rawValue: {
          'invalidRoom': 'invalid',
          'dapur': {
            'missingBrightness': {'state': true},
            'invalidState': {'state': 'true', 'brightness': 50},
            'invalidBrightness': {'state': true, 'brightness': 'none'},
            'valid': true,
          },
        },
      ),
    );

    expect(
      result.find(const DeviceAddress(roomKey: 'invalidRoom', deviceKey: 'invalid')),
      isNull,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'missingBrightness')),
      isNull,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'invalidState')),
      isNull,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'invalidBrightness')),
      isNull,
    );
    expect(
      result.find(const DeviceAddress(roomKey: 'dapur', deviceKey: 'valid')),
      const RoomDeviceValue(isOn: true),
    );
  });
}
```

- [ ] **Step 2: Run mapper tests to verify failure**

Run:

```powershell
flutter test test/room_device_mapper_test.dart
```

Expected: FAIL because DTO, mapper, and test file do not exist.

- [ ] **Step 3: Create raw room DTO**

Create `lib/features/monitoring/data/models/room_device_collection_dto.dart`:

```dart
class RoomDeviceCollectionDto {
  final Object? rawValue;

  const RoomDeviceCollectionDto({required this.rawValue});
}
```

- [ ] **Step 4: Implement room mapper**

Create `lib/features/monitoring/data/mappers/room_device_mapper.dart`:

```dart
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

RoomDeviceCollection mapRoomDeviceCollectionDtoToEntity(
  RoomDeviceCollectionDto dto,
) {
  final rawRooms = dto.rawValue;
  if (rawRooms is! Map) return RoomDeviceCollection.empty();

  final values = <DeviceAddress, RoomDeviceValue>{};
  for (final roomEntry in rawRooms.entries) {
    final roomValue = roomEntry.value;
    if (roomValue is! Map) continue;

    final roomKey = roomEntry.key.toString();
    for (final deviceEntry in roomValue.entries) {
      final deviceValue = _mapDeviceValue(deviceEntry.value);
      if (deviceValue == null) continue;
      values[DeviceAddress(
        roomKey: roomKey,
        deviceKey: deviceEntry.key.toString(),
      )] = deviceValue;
    }
  }

  return RoomDeviceCollection(values: values);
}

RoomDeviceValue? _mapDeviceValue(Object? rawValue) {
  if (rawValue is bool) {
    return RoomDeviceValue(isOn: rawValue);
  }
  if (rawValue is! Map) return null;

  final state = rawValue['state'];
  final brightness = _parseBrightness(rawValue['brightness']);
  if (state is! bool || brightness == null) return null;

  return RoomDeviceValue(isOn: state, brightness: brightness);
}

int? _parseBrightness(Object? rawValue) {
  final numeric = rawValue is num
      ? rawValue
      : rawValue is String
      ? num.tryParse(rawValue)
      : null;
  if (numeric == null) return null;
  return numeric.toInt().clamp(0, 100).toInt();
}
```

The mapper must not default a missing brightness, invalid state, invalid brightness, room scalar, or device scalar to OFF. `brightness == 0` remains non-null and therefore dimmable.

- [ ] **Step 5: Change Firebase room data source to DTO output**

Modify `lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart`:

```dart
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:firebase_database/firebase_database.dart';

abstract interface class RoomDeviceDataSource {
  Stream<RoomDeviceCollectionDto> getRoomDevicesStream();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}
```

Replace only room stream parsing with:

```dart
@override
Stream<RoomDeviceCollectionDto> getRoomDevicesStream() {
  return database.child('rooms').onValue.map(
    (event) => RoomDeviceCollectionDto(rawValue: event.snapshot.value),
  );
}
```

Delete `parseRoomDevicesData`. Keep `roomDeviceCommandPath`, `roomDeviceCommandPayload`, database path, payload branches, and existing write error text unchanged:

```dart
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
```

- [ ] **Step 6: Update Firebase data source regression tests**

Modify `test/firebase_room_device_data_source_test.dart` imports:

```dart
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
```

Replace raw wrapper parser tests with:

```dart
test('room device DTO retains raw /rooms snapshot for data mapper', () {
  const rawValue = {
    'teras': {'lampu': true},
  };
  const dto = RoomDeviceCollectionDto(rawValue: rawValue);

  expect(dto.rawValue, rawValue);
});

test('room device DTO accepts malformed snapshot without defaulting state', () {
  const dto = RoomDeviceCollectionDto(rawValue: 'invalid');
  expect(dto.rawValue, 'invalid');
});
```

Keep existing path and payload tests exactly, including expected path `commands/rooms/dapur/lampu`, dimmable payload `{'state': true, 'brightness': 75}`, and state-only bool `false`.

- [ ] **Step 7: Run data-layer tests**

Run:

```powershell
flutter test test/room_device_mapper_test.dart test/firebase_room_device_data_source_test.dart
```

Expected: PASS. No malformed node becomes `RoomDeviceValue(isOn: false)`.

---

### Task 3: Typed Repository and Use Case Pipeline

**Files:**
- Modify: `lib/features/monitoring/domain/repositories/monitoring_repository.dart:1-14`
- Modify: `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart:1-49`
- Modify: `lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart:1-11`
- Modify: `test/repository_implementation_test.dart`
- Modify: `test/use_case_test.dart`
- Modify: `test/architecture_boundary_test.dart`

**Consumes:** `RoomDeviceCollection`, `RoomDeviceCollectionDto`, and `mapRoomDeviceCollectionDtoToEntity` from Tasks 1-2.

**Produces:** `MonitoringRepository.getRoomDevicesStream()` and `WatchRoomDevicesUseCase.call()` both return `Stream<RoomDeviceCollection>`.

- [ ] **Step 1: Change repository contract**

Modify `lib/features/monitoring/domain/repositories/monitoring_repository.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';

abstract interface class MonitoringRepository {
  Stream<McbDataCollection> getMonitoringDataStream();
  Stream<RoomDeviceCollection> getRoomDevicesStream();
  Stream<bool> getConnectionStatus();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}
```

The domain contract must not import DTO, Firebase, Flutter, or raw Firebase map types.

- [ ] **Step 2: Update repository implementation**

Modify `lib/features/monitoring/data/repositories/monitoring_repository_impl.dart`:

```dart
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/room_device_mapper.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class MonitoringRepositoryImpl implements MonitoringRepository {
  final MonitoringDataSource monitoringDataSource;
  final RoomDeviceDataSource roomDeviceDataSource;

  MonitoringRepositoryImpl({
    required this.monitoringDataSource,
    required this.roomDeviceDataSource,
  });

  @override
  Stream<McbDataCollection> getMonitoringDataStream() {
    return monitoringDataSource.getMonitoringDataStream().map(
      mapRealtimeMonitoringDtoToEntity,
    );
  }

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() {
    return roomDeviceDataSource
        .getRoomDevicesStream()
        .map(mapRoomDeviceCollectionDtoToEntity);
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

- [ ] **Step 3: Update typed room use case**

Replace `lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart` with:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchRoomDevicesUseCase {
  final MonitoringRepository repository;

  WatchRoomDevicesUseCase({required this.repository});

  Stream<RoomDeviceCollection> call() {
    return repository.getRoomDevicesStream();
  }
}
```

- [ ] **Step 4: Update repository test fakes and typed stream assertions**

In `test/repository_implementation_test.dart`:

```dart
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
```

Change fake room source:

```dart
class FakeRoomDeviceDataSource implements RoomDeviceDataSource {
  final roomController = StreamController<RoomDeviceCollectionDto>.broadcast();
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
  Stream<RoomDeviceCollectionDto> getRoomDevicesStream() => roomController.stream;

  Future<void> close() => roomController.close();
}
```

Change room stream test variables and assertions:

```dart
final roomDevicesReceived = Completer<RoomDeviceCollection>();
final roomDevicesSubscription = repository.getRoomDevicesStream().listen(
  roomDevicesReceived.complete,
);

roomDeviceDataSource.roomController.add(
  const RoomDeviceCollectionDto(
    rawValue: {
      'dapur': {
        'lampu': {'state': true, 'brightness': 75},
      },
    },
  ),
);

final roomDevices = await roomDevicesReceived.future;
expect(
  roomDevices.find(
    const DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu'),
  ),
  const RoomDeviceValue(isOn: true, brightness: 75),
);
```

Keep command delegation and telemetry assertions unchanged.

- [ ] **Step 5: Update use case test fake and typed stream assertion**

In `test/use_case_test.dart`, import:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
```

Change fake room stream:

```dart
final roomController = StreamController<RoomDeviceCollection>.broadcast();
late final Stream<RoomDeviceCollection> roomStream = roomController.stream;

@override
Stream<RoomDeviceCollection> getRoomDevicesStream() => roomStream;
```

Keep `expect(rooms(), same(monitoringRepository.roomStream));`; its stream type must now be `Stream<RoomDeviceCollection>`.

- [ ] **Step 6: Run pipeline tests**

Run:

```powershell
flutter test test/repository_implementation_test.dart test/use_case_test.dart
```

Expected: FAIL before migration and PASS after repository/use case migration. Typed room values must arrive at the repository consumer; no raw map assertion remains outside data-layer tests.

- [ ] **Step 7: Add typed repository boundary assertion**

Add to `test/architecture_boundary_test.dart`:

```dart
test('room repository pipeline exposes typed collections', () {
  final repository = readProjectFile(
    'lib/features/monitoring/domain/repositories/monitoring_repository.dart',
  );
  final implementation = readProjectFile(
    'lib/features/monitoring/data/repositories/monitoring_repository_impl.dart',
  );
  final useCase = readProjectFile(
    'lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart',
  );

  expect(repository, contains('Stream<RoomDeviceCollection> getRoomDevicesStream();'));
  expect(implementation, contains('Stream<RoomDeviceCollection> getRoomDevicesStream()'));
  expect(useCase, contains('Stream<RoomDeviceCollection> call()'));
  expect(repository, isNot(contains('Map<String, dynamic>')));
  expect(useCase, isNot(contains('Map<String, dynamic>')));
});
```

---

### Task 4: Typed BLoC State, Events, and Transitions

**Files:**
- Modify: `lib/bloc/monitoring/monitoring_event.dart:1-61`
- Modify: `lib/bloc/monitoring/monitoring_state.dart:1-49`
- Modify: `lib/bloc/monitoring/monitoring_bloc.dart:1-389`
- Modify: `test/monitoring_bloc_test.dart`

**Consumes:** `Stream<RoomDeviceCollection>` from Task 3 and `DeviceAddress`/`RoomDeviceValue` from Task 1.

**Produces:** `MonitoringLoaded.deviceData`, `confirmedDeviceData`, `pendingDevices`, and `commandErrors` keyed by typed classes.

#### State and event interfaces

```dart
class MonitoringLoaded extends MonitoringState {
  final McbDataCollection mcbData;
  final bool isConnected;
  final RoomDeviceCollection deviceData;
  final RoomDeviceCollection confirmedDeviceData;
  final Set<DeviceAddress> pendingDevices;
  final Map<DeviceAddress, String> commandErrors;
}

class DeviceStateUpdated extends MonitoringEvent {
  final RoomDeviceCollection data;

  DeviceStateUpdated(this.data);
}

class ClearPendingCommand extends MonitoringEvent {
  final DeviceAddress address;

  ClearPendingCommand(this.address);
}

class CommandFailed extends MonitoringEvent {
  final DeviceAddress address;
  final String message;

  CommandFailed(this.address, this.message);
}
```

- [ ] **Step 1: Update BLoC test fake stream and imports**

In `test/monitoring_bloc_test.dart`, replace repository room stream type and add entity imports:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
```

Use:

```dart
final roomsController = StreamController<RoomDeviceCollection>.broadcast();

@override
Stream<RoomDeviceCollection> getRoomDevicesStream() => roomsController.stream;
```

- [ ] **Step 2: Update BLoC tests from raw maps to typed values**

Create helper values in `test/monitoring_bloc_test.dart`:

```dart
const terasLampu = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
const terasSanyo = DeviceAddress(roomKey: 'teras', deviceKey: 'sanyo');

RoomDeviceCollection roomState({
  required bool lampu,
  bool? sanyo,
}) {
  var collection = RoomDeviceCollection.empty().set(
    terasLampu,
    RoomDeviceValue(isOn: lampu),
  );
  if (sanyo != null) {
    collection = collection.set(
      terasSanyo,
      RoomDeviceValue(isOn: sanyo),
    );
  }
  return collection;
}
```

Replace initial stream values:

```dart
repository.roomsController.add(roomState(lampu: false));
```

Replace raw pending assertions:

```dart
expect(state.pendingDevices, contains(terasLampu));
```

Replace value assertions:

```dart
expect(state.deviceData.find(terasLampu)?.isOn, isTrue);
```

Replace error assertions:

```dart
expect(state.commandErrors.containsKey(terasLampu), isTrue);
```

- [ ] **Step 3: Add failing concurrency and timeout tests**

Add tests to `test/monitoring_bloc_test.dart`:

```dart
test('unrelated confirmed update does not erase another pending command', () async {
  bloc.add(StartMonitoring());
  await Future<void>.delayed(const Duration(milliseconds: 20));
  repository.roomsController.add(roomState(lampu: false, sanyo: false));
  await waitForState(
    bloc,
    (state) => state is MonitoringLoaded && state.confirmedDeviceData.values.length == 2,
  );

  bloc.add(
    ControlRoomDevice(
      roomName: 'Teras',
      roomKey: 'teras',
      deviceName: 'Lampu',
      deviceKey: 'lampu',
      isOn: true,
      brightness: 100,
      supportsBrightness: false,
    ),
  );
  await waitForState(
    bloc,
    (state) => state is MonitoringLoaded && state.pendingDevices.contains(terasLampu),
  );

  bloc.add(
    ControlRoomDevice(
      roomName: 'Teras',
      roomKey: 'teras',
      deviceName: 'Sanyo',
      deviceKey: 'sanyo',
      isOn: true,
      brightness: 100,
      supportsBrightness: false,
    ),
  );
  await waitForState(
    bloc,
    (state) =>
        state is MonitoringLoaded &&
        state.pendingDevices.contains(terasLampu) &&
        state.pendingDevices.contains(terasSanyo),
  );

  repository.roomsController.add(roomState(lampu: false, sanyo: true));
  await Future<void>.delayed(const Duration(milliseconds: 20));

  final state = bloc.state as MonitoringLoaded;
  expect(state.pendingDevices, contains(terasLampu));
  expect(state.deviceData.find(terasLampu)?.isOn, isTrue);
  expect(state.deviceData.find(terasSanyo)?.isOn, isTrue);
  expect(state.confirmedDeviceData.find(terasSanyo)?.isOn, isTrue);
});

test('timeout rolls back to latest confirmed value and records timeout error', () async {
  bloc.add(StartMonitoring());
  await Future<void>.delayed(const Duration(milliseconds: 20));
  repository.roomsController.add(roomState(lampu: false));
  await waitForState(
    bloc,
    (state) => state is MonitoringLoaded && state.confirmedDeviceData.find(terasLampu) != null,
  );

  bloc.add(
    ControlRoomDevice(
      roomName: 'Teras',
      roomKey: 'teras',
      deviceName: 'Lampu',
      deviceKey: 'lampu',
      isOn: true,
      brightness: 100,
      supportsBrightness: false,
    ),
  );
  await waitForState(
    bloc,
    (state) => state is MonitoringLoaded && state.pendingDevices.contains(terasLampu),
  );

  await waitForState(
    bloc,
    (state) => state is MonitoringLoaded && state.commandErrors.containsKey(terasLampu),
  );

  final state = bloc.state as MonitoringLoaded;
  expect(state.pendingDevices, isEmpty);
  expect(state.deviceData.find(terasLampu)?.isOn, isFalse);
  expect(state.confirmedDeviceData.find(terasLampu)?.isOn, isFalse);
  expect(state.commandErrors[terasLampu], 'Perintah tidak dikonfirmasi perangkat');
});
```

The timeout test may wait approximately 5 seconds because `pendingCommandTimeout` remains `Duration(seconds: 5)`. Do not shorten production timeout only to speed up this test.

- [ ] **Step 4: Run BLoC tests to verify failure**

Run:

```powershell
flutter test test/monitoring_bloc_test.dart
```

Expected: FAIL at compile time while event/state/fake stream still use raw maps and strings.

- [ ] **Step 5: Replace typed imports and state fields**

Modify `lib/bloc/monitoring/monitoring_event.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
```

Replace the device events:

```dart
class DeviceStateUpdated extends MonitoringEvent {
  final RoomDeviceCollection data;

  DeviceStateUpdated(this.data);
}

class ClearPendingCommand extends MonitoringEvent {
  final DeviceAddress address;

  ClearPendingCommand(this.address);
}

class CommandFailed extends MonitoringEvent {
  final DeviceAddress address;
  final String message;

  CommandFailed(this.address, this.message);
}
```

Modify `lib/bloc/monitoring/monitoring_state.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
```

Replace `MonitoringLoaded` with:

```dart
class MonitoringLoaded extends MonitoringState {
  final McbDataCollection mcbData;
  final bool isConnected;
  final RoomDeviceCollection deviceData;
  final RoomDeviceCollection confirmedDeviceData;
  final Set<DeviceAddress> pendingDevices;
  final Map<DeviceAddress, String> commandErrors;

  MonitoringLoaded({
    required this.mcbData,
    required this.isConnected,
    RoomDeviceCollection? deviceData,
    RoomDeviceCollection? confirmedDeviceData,
    Set<DeviceAddress>? pendingDevices,
    Map<DeviceAddress, String>? commandErrors,
  }) : deviceData = deviceData ?? RoomDeviceCollection.empty(),
       confirmedDeviceData =
           confirmedDeviceData ?? RoomDeviceCollection.empty(),
       pendingDevices = Set<DeviceAddress>.unmodifiable(
         pendingDevices ?? const {},
       ),
       commandErrors = Map<DeviceAddress, String>.unmodifiable(
         commandErrors ?? const {},
       );

  MonitoringLoaded copyWith({
    McbDataCollection? mcbData,
    bool? isConnected,
    RoomDeviceCollection? deviceData,
    RoomDeviceCollection? confirmedDeviceData,
    Set<DeviceAddress>? pendingDevices,
    Map<DeviceAddress, String>? commandErrors,
  }) {
    return MonitoringLoaded(
      mcbData: mcbData ?? this.mcbData,
      isConnected: isConnected ?? this.isConnected,
      deviceData: deviceData ?? this.deviceData,
      confirmedDeviceData: confirmedDeviceData ?? this.confirmedDeviceData,
      pendingDevices: pendingDevices ?? this.pendingDevices,
      commandErrors: commandErrors ?? this.commandErrors,
    );
  }
}
```


- [ ] **Step 6: Replace BLoC command transition with typed collection**

In `lib/bloc/monitoring/monitoring_bloc.dart`, add:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
```

Change timer field:

```dart
final Map<DeviceAddress, Timer> _pendingTimers = {};
```

Replace `_onControlRoomDevice` and remove `_buildOptimisticDeviceData` map implementation with:

```dart
Future<void> _onControlRoomDevice(
  ControlRoomDevice event,
  Emitter<MonitoringState> emit,
) async {
  final currentState = state;
  if (currentState is! MonitoringLoaded) return;

  final address = DeviceAddress(
    roomKey: event.roomKey,
    deviceKey: event.deviceKey,
  );
  if (currentState.pendingDevices.contains(address)) return;

  final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
    ..add(address);
  final commandErrors = Map<DeviceAddress, String>.from(currentState.commandErrors)
    ..remove(address);
  final optimisticData = _buildOptimisticDeviceData(
    currentState.deviceData,
    address,
    event.isOn,
    event.brightness,
    event.supportsBrightness,
  );

  emit(
    currentState.copyWith(
      deviceData: optimisticData,
      pendingDevices: pendingDevices,
      commandErrors: commandErrors,
    ),
  );

  _pendingTimers[address]?.cancel();
  _pendingTimers[address] = Timer(pendingCommandTimeout, () {
    if (!isClosed) add(ClearPendingCommand(address));
  });

  try {
    await controlRoomDevice(
      roomKey: event.roomKey,
      deviceKey: event.deviceKey,
      isOn: event.isOn,
      brightness: event.brightness.toInt(),
      supportsBrightness: event.supportsBrightness,
    );
  } catch (_) {
    if (!isClosed) add(CommandFailed(address, 'Perintah gagal dikirim'));
  }
}

RoomDeviceCollection _buildOptimisticDeviceData(
  RoomDeviceCollection currentData,
  DeviceAddress address,
  bool isOn,
  double brightness,
  bool supportsBrightness,
) {
  final normalizedBrightness = brightness.round().clamp(0, 100).toInt();
  final value = supportsBrightness
      ? RoomDeviceValue(
          isOn: isOn,
          brightness: isOn ? normalizedBrightness : 0,
        )
      : RoomDeviceValue(isOn: isOn);
  return currentData.set(address, value);
}
```

`controlRoomDevice` tetap memakai parameter room/device/isOn/brightness/supportsBrightness sehingga command payload dan firmware contract tidak berubah.

- [ ] **Step 7: Replace typed confirmed/visible merge transition**

Replace `_onDeviceStateUpdated` with:

```dart
void _onDeviceStateUpdated(
  DeviceStateUpdated event,
  Emitter<MonitoringState> emit,
) {
  final currentState = state;
  if (currentState is! MonitoringLoaded) {
    emit(
      MonitoringLoaded(
        mcbData: McbDataCollection.empty(),
        isConnected: false,
        deviceData: event.data,
        confirmedDeviceData: event.data,
      ),
    );
    return;
  }

  var visibleData = event.data;
  final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices);
  final commandErrors = Map<DeviceAddress, String>.from(currentState.commandErrors);

  for (final address in currentState.pendingDevices) {
    final desired = currentState.deviceData.find(address);
    final confirmed = event.data.find(address);

    if (desired != null && desired == confirmed) {
      pendingDevices.remove(address);
      commandErrors.remove(address);
      _pendingTimers.remove(address)?.cancel();
    } else if (desired != null) {
      visibleData = visibleData.set(address, desired);
    }
  }

  emit(
    currentState.copyWith(
      deviceData: visibleData,
      confirmedDeviceData: event.data,
      pendingDevices: pendingDevices,
      commandErrors: commandErrors,
    ),
  );
}
```

This makes every `/rooms` snapshot the newest confirmed snapshot, while retaining only the desired value for each still-pending address. An update for device B cannot replace pending desired value for device A.

- [ ] **Step 8: Replace timeout, failure, and rollback transitions**

Replace `_onClearPendingCommand`, `_onCommandFailed`, and `_restorePendingValues` with:

```dart
void _onClearPendingCommand(
  ClearPendingCommand event,
  Emitter<MonitoringState> emit,
) {
  final currentState = state;
  if (currentState is! MonitoringLoaded ||
      !currentState.pendingDevices.contains(event.address)) {
    return;
  }

  final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
    ..remove(event.address);
  final commandErrors = Map<DeviceAddress, String>.from(currentState.commandErrors)
    ..[event.address] = 'Perintah tidak dikonfirmasi perangkat';
  _pendingTimers.remove(event.address)?.cancel();

  emit(
    currentState.copyWith(
      deviceData: _restorePendingValues(currentState, pendingDevices),
      pendingDevices: pendingDevices,
      commandErrors: commandErrors,
    ),
  );
}

void _onCommandFailed(CommandFailed event, Emitter<MonitoringState> emit) {
  final currentState = state;
  if (currentState is! MonitoringLoaded) return;

  final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
    ..remove(event.address);
  final commandErrors = Map<DeviceAddress, String>.from(currentState.commandErrors)
    ..[event.address] = event.message;
  _pendingTimers.remove(event.address)?.cancel();

  emit(
    currentState.copyWith(
      deviceData: _restorePendingValues(currentState, pendingDevices),
      pendingDevices: pendingDevices,
      commandErrors: commandErrors,
    ),
  );
}

RoomDeviceCollection _restorePendingValues(
  MonitoringLoaded currentState,
  Set<DeviceAddress> pendingDevices,
) {
  var data = currentState.confirmedDeviceData;
  for (final address in pendingDevices) {
    final desired = currentState.deviceData.find(address);
    if (desired != null) data = data.set(address, desired);
  }
  return data;
}
```

Remove `_deviceNode`, `_setDeviceNode`, `_deviceValuesMatch`, and `_deepCopyMap`. No raw Firebase keys, map casts, string splitting, or map deep-copy logic may remain in BLoC.

- [ ] **Step 9: Update device stream callback**

The existing subscription remains lifecycle-equivalent but now receives entity values:

```dart
_deviceDataSubscription = watchRoomDevices().listen(
  (data) => add(DeviceStateUpdated(data)),
  onError: (Object error) {
    if (!isClosed) {
      add(MonitoringStreamFailed('Status perangkat tidak tersedia'));
    }
  },
);
```

Do not change `_monitoringActive`, stream error messages, subscription cancellation, `pendingCommandTimeout`, or `close()` lifecycle behavior.

- [ ] **Step 10: Run BLoC tests**

Run:

```powershell
flutter test test/monitoring_bloc_test.dart
```

Expected: PASS for idempotent start, matching confirmation, write failure rollback, timeout rollback, duplicate pending rejection, unrelated-device update, and per-device error isolation.

- [ ] **Step 11: Run content boundary check**

Search these files for raw room parsing tokens:

```text
lib/bloc/monitoring/monitoring_event.dart
lib/bloc/monitoring/monitoring_state.dart
lib/bloc/monitoring/monitoring_bloc.dart
```

Expected: no `Map<String, dynamic>`, `['rooms']`, `['state']`, `['brightness']`, `.split('/')`, `_deviceNode`, `_setDeviceNode`, or `_deepCopyMap`.

---

### Task 5: Presentation Device View State and Mapper

**Files:**
- Create: `lib/features/monitoring/presentation/models/device_control_view_state.dart`
- Create: `lib/features/monitoring/presentation/mappers/device_control_view_mapper.dart`
- Create: `test/device_control_view_mapper_test.dart`
- Modify: `test/architecture_boundary_test.dart`

**Interfaces:**

```dart
enum DeviceControlPhase {
  unknown,
  off,
  on,
  pending,
  failed,
}

class DeviceControlViewState {
  final DeviceControlPhase phase;
  final RoomDeviceValue? value;
  final String? errorMessage;

  const DeviceControlViewState({
    required this.phase,
    required this.value,
    required this.errorMessage,
  });

  bool get hasKnownValue => value != null;
  bool get controlsEnabled => value != null && phase != DeviceControlPhase.pending;
}

DeviceControlViewState mapDeviceControlViewState({
  required RoomDeviceCollection visibleDevices,
  required DeviceAddress address,
  required bool isPending,
  required String? errorMessage,
});
```

- [ ] **Step 1: Add failing presentation mapper tests**

Create `test/device_control_view_mapper_test.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/mappers/device_control_view_mapper.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const address = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');

  test('missing value maps to unknown and disabled controls', () {
    final result = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty(),
      address: address,
      isPending: false,
      errorMessage: null,
    );

    expect(result.phase, DeviceControlPhase.unknown);
    expect(result.value, isNull);
    expect(result.controlsEnabled, isFalse);
  });

  test('known off and on values map to distinct phases', () {
    final off = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: false),
      ),
      address: address,
      isPending: false,
      errorMessage: null,
    );
    final on = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: true),
      ),
      address: address,
      isPending: false,
      errorMessage: null,
    );

    expect(off.phase, DeviceControlPhase.off);
    expect(off.controlsEnabled, isTrue);
    expect(on.phase, DeviceControlPhase.on);
    expect(on.controlsEnabled, isTrue);
  });

  test('pending takes priority over known value and disables controls', () {
    final result = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: true),
      ),
      address: address,
      isPending: true,
      errorMessage: null,
    );

    expect(result.phase, DeviceControlPhase.pending);
    expect(result.value?.isOn, isTrue);
    expect(result.controlsEnabled, isFalse);
  });

  test('failed takes priority and enables only when value is known', () {
    final known = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: false),
      ),
      address: address,
      isPending: false,
      errorMessage: 'Perintah gagal dikirim',
    );
    final unknown = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty(),
      address: address,
      isPending: false,
      errorMessage: 'Perintah tidak dikonfirmasi perangkat',
    );

    expect(known.phase, DeviceControlPhase.failed);
    expect(known.value?.isOn, isFalse);
    expect(known.errorMessage, 'Perintah gagal dikirim');
    expect(known.controlsEnabled, isTrue);
    expect(unknown.phase, DeviceControlPhase.failed);
    expect(unknown.value, isNull);
    expect(unknown.controlsEnabled, isFalse);
  });
}
```

- [ ] **Step 2: Run mapper tests to verify failure**

Run:

```powershell
flutter test test/device_control_view_mapper_test.dart
```

Expected: FAIL because view-state and mapper files do not exist.

- [ ] **Step 3: Implement view-state model**

Create `lib/features/monitoring/presentation/models/device_control_view_state.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

enum DeviceControlPhase {
  unknown,
  off,
  on,
  pending,
  failed,
}

class DeviceControlViewState {
  final DeviceControlPhase phase;
  final RoomDeviceValue? value;
  final String? errorMessage;

  const DeviceControlViewState({
    required this.phase,
    required this.value,
    required this.errorMessage,
  });

  bool get hasKnownValue => value != null;
  bool get controlsEnabled => value != null && phase != DeviceControlPhase.pending;
}
```

- [ ] **Step 4: Implement phase mapper**

Create `lib/features/monitoring/presentation/mappers/device_control_view_mapper.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';

DeviceControlViewState mapDeviceControlViewState({
  required RoomDeviceCollection visibleDevices,
  required DeviceAddress address,
  required bool isPending,
  required String? errorMessage,
}) {
  final value = visibleDevices.find(address);
  final phase = errorMessage != null
      ? DeviceControlPhase.failed
      : isPending
      ? DeviceControlPhase.pending
      : value == null
      ? DeviceControlPhase.unknown
      : value.isOn
      ? DeviceControlPhase.on
      : DeviceControlPhase.off;

  return DeviceControlViewState(
    phase: phase,
    value: value,
    errorMessage: errorMessage,
  );
}
```

Priority must remain exactly: `errorMessage != null`, then `isPending`, then missing value, then `isOn`.

- [ ] **Step 5: Run presentation mapper tests**

Run:

```powershell
flutter test test/device_control_view_mapper_test.dart
```

Expected: PASS for unknown/off/on/pending/failed and known-value control availability.

- [ ] **Step 6: Add presentation boundary assertions**

Add to `test/architecture_boundary_test.dart`:

```dart
test('device presentation mapper avoids data and Firebase imports', () {
  const files = [
    'lib/features/monitoring/presentation/models/device_control_view_state.dart',
    'lib/features/monitoring/presentation/mappers/device_control_view_mapper.dart',
  ];
  const forbiddenTokens = [
    '/data/',
    'package:flutter',
    'package:flutter_bloc',
    'package:firebase_',
    'package:cloud_firestore/',
  ];

  for (final file in files) {
    final source = readProjectFile(file);
    for (final token in forbiddenTokens) {
      expect(source, isNot(contains(token)), reason: file);
    }
  }
});
```

---

### Task 6: Migrate Monitoring Screen to Typed Status View

**Files:**
- Modify: `lib/screen/monitoring.dart:1-701`
- Create: `test/monitoring_device_widget_test.dart`

**Consumes:** `RoomDeviceCollection`, `DeviceAddress`, `DeviceControlViewState`, and `mapDeviceControlViewState` from Tasks 1 and 5.

- [ ] **Step 1: Add typed imports and widget test fixtures**

Add to `lib/screen/monitoring.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/mappers/device_control_view_mapper.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
```

Create `test/monitoring_device_widget_test.dart` with:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
import 'package:esh/screen/monitoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unknown status is not rendered as Mati', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeviceStatusCard(
            name: 'Lampu',
            supportsBrightness: true,
            viewState: DeviceControlViewState(
              phase: DeviceControlPhase.unknown,
              value: null,
              errorMessage: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Status belum tersedia'), findsOneWidget);
    expect(find.text('Mati'), findsNothing);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('dimmable status displays preserved zero brightness', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeviceStatusCard(
            name: 'Lampu',
            supportsBrightness: true,
            viewState: DeviceControlViewState(
              phase: DeviceControlPhase.off,
              value: RoomDeviceValue(isOn: false, brightness: 0),
              errorMessage: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mati'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byIcon(Icons.power_off), findsOneWidget);
  });

  testWidgets('failed status renders error text and error icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeviceStatusCard(
            name: 'Lampu',
            viewState: DeviceControlViewState(
              phase: DeviceControlPhase.failed,
              value: RoomDeviceValue(isOn: false),
              errorMessage: 'Perintah gagal dikirim',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Perintah gagal dikirim'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run widget tests to verify failure**

Run:

```powershell
flutter test test/monitoring_device_widget_test.dart
```

Expected: FAIL because `DeviceStatusCard` still accepts `isOn`/`brightness` instead of `viewState` and still renders missing data as `Mati`.

- [ ] **Step 3: Pass typed state through electronic section**

Replace `_buildElektronikSection` with:

```dart
Widget _buildElektronikSection(
  RoomDeviceCollection deviceData,
  Set<DeviceAddress> pendingDevices,
  Map<DeviceAddress, String> commandErrors,
) {
  return Column(
    children: roomDeviceConfigs.map((roomConfig) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _buildRoomElectronicCard(
          roomConfig,
          deviceData,
          pendingDevices,
          commandErrors,
        ),
      );
    }).toList(),
  );
}
```

At the existing `Alat Elektronik` branch, call:

```dart
_buildElektronikSection(
  state.deviceData,
  state.pendingDevices,
  state.commandErrors,
),
```

Replace `_buildRoomElectronicCard` signature and device mapping with:

```dart
Widget _buildRoomElectronicCard(
  RoomDeviceConfig roomConfig,
  RoomDeviceCollection deviceData,
  Set<DeviceAddress> pendingDevices,
  Map<DeviceAddress, String> commandErrors,
) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: _cardStyle(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.meeting_room_rounded,
              color: Colors.amber,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              roomConfig.displayName,
              style: _textStyle(bold: true, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...roomConfig.devices.map((device) {
          final address = DeviceAddress(
            roomKey: roomConfig.roomKey,
            deviceKey: device.deviceKey,
          );
          final viewState = mapDeviceControlViewState(
            visibleDevices: deviceData,
            address: address,
            isPending: pendingDevices.contains(address),
            errorMessage: commandErrors[address],
          );
          return DeviceStatusCard(
            name: device.displayName,
            supportsBrightness: device.supportsBrightness,
            viewState: viewState,
          );
        }),
      ],
    ),
  );
}
```

- [ ] **Step 4: Replace `DeviceStatusCard` raw bool API and render status semantics**

Replace `DeviceStatusCard` with this API and behavior:

```dart
class DeviceStatusCard extends StatelessWidget {
  final String name;
  final bool supportsBrightness;
  final DeviceControlViewState viewState;

  const DeviceStatusCard({
    super.key,
    required this.name,
    required this.viewState,
    this.supportsBrightness = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(viewState);
    final color = _statusColor(viewState.phase);
    final icon = _statusIcon(viewState.phase);
    final brightness = viewState.value?.brightness;

    return Semantics(
      container: true,
      label: '$name, $label',
      value: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            if (supportsBrightness && brightness != null) ...[
              Text(
                '$brightness%',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (viewState.phase == DeviceControlPhase.pending)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (viewState.phase == DeviceControlPhase.pending)
                      const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(DeviceControlViewState state) {
    if (state.phase == DeviceControlPhase.unknown) return 'Status belum tersedia';
    if (state.phase == DeviceControlPhase.pending) return 'Menunggu konfirmasi';
    if (state.phase == DeviceControlPhase.failed) {
      return state.errorMessage ?? 'Perintah gagal';
    }
    return state.phase == DeviceControlPhase.on ? 'Nyala' : 'Mati';
  }

  Color _statusColor(DeviceControlPhase phase) {
    if (phase == DeviceControlPhase.on) return Colors.green;
    if (phase == DeviceControlPhase.off) return Colors.red;
    if (phase == DeviceControlPhase.pending) return Colors.amber;
    if (phase == DeviceControlPhase.failed) return Colors.redAccent;
    return Colors.grey;
  }

  IconData _statusIcon(DeviceControlPhase phase) {
    if (phase == DeviceControlPhase.on) return Icons.power;
    if (phase == DeviceControlPhase.off) return Icons.power_off;
    if (phase == DeviceControlPhase.pending) return Icons.sync;
    if (phase == DeviceControlPhase.failed) return Icons.error_outline;
    return Icons.help_outline;
  }
}
```

Use `DeviceStatusCard` text and icon as primary signals. Color remains supporting signal. Keep label wrapping inside the existing row; device name remains ellipsized and never removed.

- [ ] **Step 5: Run monitoring widget tests**

Run:

```powershell
flutter test test/monitoring_device_widget_test.dart
```

Expected: PASS for unknown, dimmable zero brightness, failed error, text/icon semantics, and no `Mati` fallback for missing data.

- [ ] **Step 6: Check monitoring screen boundary**

Search `lib/screen/monitoring.dart` for:

```text
Map<String, dynamic>
['rooms']
['state']
['brightness']
```

Expected: no matches. Existing telemetry map parsing and cost/emission UI remain untouched because they are outside room-device state path.

---

### Task 7: Migrate Control Screen and Device Controls

**Files:**
- Modify: `lib/screen/control.dart:1-672`
- Modify: `test/monitoring_device_widget_test.dart`

**Consumes:** Typed BLoC state from Task 4 and presentation mapper from Task 5.

- [ ] **Step 1: Add imports and typed control fixture**

Add to `lib/screen/control.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/mappers/device_control_view_mapper.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
```

- [ ] **Step 2: Render typed empty state as unknown devices**

Remove the condition:

```dart
if (state.deviceData['rooms'] is! Map) {
  return const Center(
    child: Text(
      'Menunggu status perangkat...',
      style: TextStyle(color: Colors.white),
    ),
  );
}
```

An empty `RoomDeviceCollection` must still render hardware and control cards. Each missing device then maps to `Status belum tersedia`, with controls disabled. This prevents loading from being shown as OFF while preserving the existing scroll/card hierarchy.

Update the card call:

```dart
_buildRoomControlCard(
  roomConfig,
  devices,
  state.deviceData,
  state.pendingDevices,
  state.commandErrors,
),
```

- [ ] **Step 3: Replace `_buildRoomControlCard` data API**

Replace the method signature and body device-state mapping with:

```dart
Widget _buildRoomControlCard(
  RoomDeviceConfig roomConfig,
  List<DeviceConfig> devices,
  RoomDeviceCollection deviceData,
  Set<DeviceAddress> pendingDevices,
  Map<DeviceAddress, String> commandErrors,
) {
  return Column(
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardStyle(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Status Hardware ${roomConfig.displayName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...devices.map((device) {
              final address = DeviceAddress(
                roomKey: roomConfig.roomKey,
                deviceKey: device.deviceKey,
              );
              final viewState = mapDeviceControlViewState(
                visibleDevices: deviceData,
                address: address,
                isPending: pendingDevices.contains(address),
                errorMessage: commandErrors[address],
              );
              return _buildStatusItem(
                device.displayName,
                device.supportsBrightness,
                viewState,
              );
            }),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardStyle(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: Colors.amber, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Panel Kontrol ${roomConfig.displayName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...devices.map((device) {
              final address = DeviceAddress(
                roomKey: roomConfig.roomKey,
                deviceKey: device.deviceKey,
              );
              final viewState = mapDeviceControlViewState(
                visibleDevices: deviceData,
                address: address,
                isPending: pendingDevices.contains(address),
                errorMessage: commandErrors[address],
              );
              return _ControlActionWidget(
                roomName: roomConfig.displayName,
                roomKey: roomConfig.roomKey,
                name: device.displayName,
                deviceKey: device.deviceKey,
                supportsBrightness: device.supportsBrightness,
                viewState: viewState,
              );
            }),
          ],
        ),
      ),
    ],
  );
}
```

- [ ] **Step 4: Replace status item parser with view-state renderer**

Delete `_getDeviceNode`, `_getDeviceState`, and `_getDeviceBrightness`. Replace `_buildStatusItem` with:

```dart
Widget _buildStatusItem(
  String name,
  bool supportsBrightness,
  DeviceControlViewState viewState,
) {
  final label = _statusLabel(viewState);
  final color = _statusColor(viewState.phase);
  final brightness = viewState.value?.brightness;

  return Semantics(
    container: true,
    label: '$name, $label',
    value: label,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(_statusIcon(viewState.phase), color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          if (supportsBrightness && brightness != null) ...[
            Text(
              '$brightness%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _statusLabel(DeviceControlViewState state) {
  if (state.phase == DeviceControlPhase.unknown) return 'Status belum tersedia';
  if (state.phase == DeviceControlPhase.pending) return 'Menunggu konfirmasi';
  if (state.phase == DeviceControlPhase.failed) {
    return state.errorMessage ?? 'Perintah gagal';
  }
  return state.phase == DeviceControlPhase.on ? 'Nyala' : 'Mati';
}

Color _statusColor(DeviceControlPhase phase) {
  if (phase == DeviceControlPhase.on) return Colors.green;
  if (phase == DeviceControlPhase.off) return Colors.red;
  if (phase == DeviceControlPhase.pending) return Colors.amber;
  if (phase == DeviceControlPhase.failed) return Colors.redAccent;
  return Colors.grey;
}

IconData _statusIcon(DeviceControlPhase phase) {
  if (phase == DeviceControlPhase.on) return Icons.power;
  if (phase == DeviceControlPhase.off) return Icons.power_off;
  if (phase == DeviceControlPhase.pending) return Icons.sync;
  if (phase == DeviceControlPhase.failed) return Icons.error_outline;
  return Icons.help_outline;
}
```

- [ ] **Step 5: Replace `_ControlActionWidget` state inputs**

Replace its fields and constructor inputs:

```dart
class _ControlActionWidget extends StatefulWidget {
  final String roomName;
  final String roomKey;
  final String name;
  final String deviceKey;
  final bool supportsBrightness;
  final DeviceControlViewState viewState;

  const _ControlActionWidget({
    required this.roomName,
    required this.roomKey,
    required this.name,
    required this.deviceKey,
    required this.supportsBrightness,
    required this.viewState,
  });

  @override
  State<_ControlActionWidget> createState() => _ControlActionWidgetState();
}
```

Replace initialization and widget synchronization:

```dart
void _syncFromViewState() {
  final value = widget.viewState.value;
  _localBrightness = value?.brightness?.toDouble() ?? 0;
  _isOn = value?.isOn ?? false;
}

@override
void initState() {
  super.initState();
  _syncFromViewState();
}

@override
void didUpdateWidget(covariant _ControlActionWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (!_isEditing && widget.viewState.phase != DeviceControlPhase.pending) {
    _syncFromViewState();
  }
}

bool get _canInteract => widget.viewState.controlsEnabled;
```

Replace `_sendControlCommand` guard:

```dart
void _sendControlCommand(bool turnOn, double brightnessVal) {
  if (!_canInteract) return;

  context.read<MonitoringBloc>().add(
    ControlRoomDevice(
      roomName: widget.roomName,
      roomKey: widget.roomKey,
      deviceName: widget.name,
      deviceKey: widget.deviceKey,
      isOn: turnOn,
      brightness: brightnessVal,
      supportsBrightness: widget.supportsBrightness,
    ),
  );
  setState(() {
    _isEditing = false;
    _isOn = turnOn;
  });
}
```

Keep `deviceName` named parameter unchanged; current `ControlRoomDevice` exposes `deviceName`, and this task must not rename event public fields.

- [ ] **Step 6: Render pending/failed status text in control action**

Replace the header and error section in `_ControlActionWidget.build` with:

```dart
Row(
  children: [
    Expanded(
      child: Text(
        widget.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    if (widget.viewState.phase == DeviceControlPhase.pending)
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
  ],
),
if (widget.viewState.errorMessage != null) ...[
  const SizedBox(height: 4),
  Semantics(
    liveRegion: true,
    child: Text(
      widget.viewState.errorMessage!,
      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
    ),
  ),
],
const SizedBox(height: 8),
```

Keep `Nyalakan`, `Matikan`, `Nyala`, `Mati`, and `Send` labels unchanged.

- [ ] **Step 7: Disable controls only for unknown/pending without disabling known failed controls**

Apply `_canInteract` to all command controls:

```dart
onPressed: _canInteract ? () => _confirmToggle(true) : null
```

```dart
onPressed: _canInteract ? () => _confirmToggle(false) : null
```

```dart
onPressed: _canInteract
    ? () {
        setState(() {
          _isOn = true;
          if (_localBrightness == 0) _localBrightness = 100;
        });
      }
    : null
```

```dart
onPressed: _canInteract
    ? () {
        setState(() {
          _isOn = false;
          _localBrightness = 0;
        });
      }
    : null
```

```dart
onChangeStart: _canInteract && _isOn
    ? (value) => setState(() => _isEditing = true)
    : null,
onChanged: _canInteract && _isOn
    ? (value) => setState(() => _localBrightness = value)
    : null,
onPressed: _canInteract
    ? () => _sendControlCommand(_isOn, _localBrightness)
    : null,
```

This preserves existing off-slider behavior while additionally disabling slider and commands for unknown/pending. A failed command with a known confirmed value has `_canInteract == true` and can be retried.

- [ ] **Step 8: Add ControlPage integration assertions**

Before this test, extend `test/monitoring_device_widget_test.dart` imports with:

```dart
import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:esh/screen/control.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
```

Add this complete typed fake before `main()`:

```dart
class FakeMonitoringRepository implements MonitoringRepository {
  final roomsController = StreamController<RoomDeviceCollection>.broadcast();

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {}

  @override
  Stream<bool> getConnectionStatus() => const Stream.empty();

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => const Stream.empty();

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() => roomsController.stream;

  Future<void> close() => roomsController.close();
}

MonitoringBloc createMonitoringBloc(FakeMonitoringRepository repository) {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(repository: repository),
    watchConnectionStatus: WatchConnectionStatusUseCase(repository: repository),
    watchRoomDevices: WatchRoomDevicesUseCase(repository: repository),
    controlRoomDevice: ControlRoomDeviceUseCase(repository: repository),
  );
}
```

Add test using local router context required by `PageSelector`:

```dart
testWidgets('pending command disables only related control', (tester) async {
  final repository = FakeMonitoringRepository();
  final bloc = createMonitoringBloc(repository);
  final router = GoRouter(
    initialLocation: '/control',
    routes: [
      GoRoute(
        path: '/control',
        builder: (context, state) => BlocProvider.value(
          value: bloc,
          child: const ControlPage(),
        ),
      ),
    ],
  );
  addTearDown(() async {
    router.dispose();
    await bloc.close();
    await repository.close();
  });

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();

  var devices = RoomDeviceCollection.empty()
      .set(
        const DeviceAddress(roomKey: 'teras', deviceKey: 'lampu'),
        const RoomDeviceValue(isOn: false),
      )
      .set(
        const DeviceAddress(roomKey: 'teras', deviceKey: 'sanyo'),
        const RoomDeviceValue(isOn: false),
      );
  bloc.add(DeviceStateUpdated(devices));
  await tester.pump();

  bloc.add(
    ControlRoomDevice(
      roomName: 'Teras',
      roomKey: 'teras',
      deviceName: 'Lampu',
      deviceKey: 'lampu',
      isOn: true,
      brightness: 100,
      supportsBrightness: false,
    ),
  );
  await tester.pump();

  final buttons = tester
      .widgetList<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Nyalakan'),
      )
      .toList();
  expect(buttons, hasLength(2));
  expect(buttons[0].onPressed, isNull);
  expect(buttons[1].onPressed, isNotNull);
});
```

No production route changes are allowed. The fake repository returns `Stream<RoomDeviceCollection>` and contains no raw room map.

- [ ] **Step 9: Run control widget tests**

Run:

```powershell
flutter test test/monitoring_device_widget_test.dart
```

Expected: PASS for unknown label, pending disabled control, failed error text, known failed control enabled, state-only brightness hidden, dimmable brightness shown, and 320px/2x layout.

- [ ] **Step 10: Check control screen boundary**

Search `lib/screen/control.dart` for:

```text
Map<String, dynamic>
['rooms']
['state']
['brightness']
.split('/')
```

Expected: no matches.

---

### Task 8: Architecture, Regression, and Dependency Checks

**Files:**
- Modify: `test/architecture_boundary_test.dart`
- Modify: `test/app_dependencies_test.dart`
- Modify: `test/repository_implementation_test.dart`
- Modify: `test/use_case_test.dart`
- Modify: `test/monitoring_bloc_test.dart`

- [ ] **Step 1: Add room-state boundary test**

Add to `test/architecture_boundary_test.dart`:

```dart
test('raw room maps stay inside data DTO and mapper files', () {
  const typedConsumerFiles = [
    'lib/features/monitoring/domain/repositories/monitoring_repository.dart',
    'lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart',
    'lib/bloc/monitoring/monitoring_event.dart',
    'lib/bloc/monitoring/monitoring_state.dart',
    'lib/bloc/monitoring/monitoring_bloc.dart',
    'lib/screen/monitoring.dart',
    'lib/screen/control.dart',
  ];
  const forbiddenTokens = [
    'Map<String, dynamic>',
    'Map<dynamic, dynamic>',
    "['rooms']",
    "['state']",
    "['brightness']",
    '.split(\'/\')',
  ];

  for (final file in typedConsumerFiles) {
    final source = readProjectFile(file);
    for (final token in forbiddenTokens) {
      expect(source, isNot(contains(token)), reason: '$file contains $token');
    }
  }
});

test('room mapper owns Firebase device node keys', () {
  final mapper = readProjectFile(
    'lib/features/monitoring/data/mappers/room_device_mapper.dart',
  );
  final dataSource = readProjectFile(
    'lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart',
  );

  expect(mapper, contains("rawValue['state']"));
  expect(mapper, contains("rawValue['brightness']"));
  expect(dataSource, isNot(contains("['state']")));
  expect(dataSource, isNot(contains("['brightness']")));
  expect(dataSource, contains("child('rooms')"));
});

test('room data source and repository use DTO/entity boundary', () {
  final dataSource = readProjectFile(
    'lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart',
  );
  final repository = readProjectFile(
    'lib/features/monitoring/data/repositories/monitoring_repository_impl.dart',
  );

  expect(dataSource, contains('Stream<RoomDeviceCollectionDto>'));
  expect(repository, contains('mapRoomDeviceCollectionDtoToEntity'));
  expect(repository, contains('Stream<RoomDeviceCollection>'));
  expect(repository, isNot(contains('Stream<Map<String, dynamic>>')));
});
```

- [ ] **Step 2: Update fake repository interfaces in all tests**

Every `implements MonitoringRepository` fake must use:

```dart
@override
Stream<RoomDeviceCollection> getRoomDevicesStream() => const Stream.empty();
```

Every `implements RoomDeviceDataSource` fake must use:

```dart
final roomController = StreamController<RoomDeviceCollectionDto>.broadcast();

@override
Stream<RoomDeviceCollectionDto> getRoomDevicesStream() => roomController.stream;
```

Update imports only to the typed entity/DTO paths. Do not introduce raw room maps into tests outside `test/room_device_mapper_test.dart` and DTO/data-source boundary assertions.

- [ ] **Step 3: Keep dependency injection behavior unchanged**

Run existing dependency test:

```powershell
flutter test test/app_dependencies_test.dart
```

Expected: PASS. `AppDependencies.createMonitoringBloc()` still returns `MonitoringBloc`; its existing use-case construction automatically uses the typed repository contract. No Firebase initialization, router, provider, or route change is required.

- [ ] **Step 4: Run focused architecture and regression suite**

Run:

```powershell
flutter test test/domain_entities_test.dart test/room_device_mapper_test.dart test/firebase_room_device_data_source_test.dart test/repository_implementation_test.dart test/use_case_test.dart test/monitoring_bloc_test.dart test/device_control_view_mapper_test.dart test/monitoring_device_widget_test.dart test/app_dependencies_test.dart test/architecture_boundary_test.dart
```

Expected: PASS. The only room schema literals allowed in production code are the Firebase `child('rooms')` path and mapper node parsing; no raw room map reaches typed consumers.

---

### Task 9: Full Verification and Scope Audit

**Files:**
- No additional production files.
- Verification covers all Plan 7 files listed above.

- [ ] **Step 1: Format Plan 7 Dart/test scope**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib/features/monitoring/domain/entities/room_device_state.dart lib/features/monitoring/domain/entities/room_device_collection.dart lib/features/monitoring/data/models/room_device_collection_dto.dart lib/features/monitoring/data/mappers/room_device_mapper.dart lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart lib/features/monitoring/data/repositories/monitoring_repository_impl.dart lib/features/monitoring/domain/repositories/monitoring_repository.dart lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart lib/features/monitoring/presentation/models/device_control_view_state.dart lib/features/monitoring/presentation/mappers/device_control_view_mapper.dart lib/bloc/monitoring/monitoring_event.dart lib/bloc/monitoring/monitoring_state.dart lib/bloc/monitoring/monitoring_bloc.dart lib/screen/monitoring.dart lib/screen/control.dart test/domain_entities_test.dart test/room_device_mapper_test.dart test/firebase_room_device_data_source_test.dart test/repository_implementation_test.dart test/use_case_test.dart test/monitoring_bloc_test.dart test/device_control_view_mapper_test.dart test/monitoring_device_widget_test.dart test/architecture_boundary_test.dart test/app_dependencies_test.dart
```

Expected: no formatting changes required. If formatting reports differences, format only listed Plan 7 files and rerun the same command. Do not format unrelated worktree files.

- [ ] **Step 2: Run analyzer**

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

Expected: all tests pass, including existing history, telemetry, architecture, and responsive tests.

- [ ] **Step 4: Run debug APK build**

Run:

```powershell
flutter build apk --debug
```

Expected: command succeeds and creates `build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 5: Run raw-map and Firebase-key scope audit**

Search production files:

```powershell
rg "Map<String, dynamic>|Map<dynamic, dynamic>|\['rooms'\]|\['state'\]|\['brightness'\]|split\('/'\)" lib/features/monitoring/domain lib/bloc/monitoring lib/screen/monitoring.dart lib/screen/control.dart
```

Expected: no result in typed consumers. Any result must be limited to `lib/features/monitoring/data/models/room_device_collection_dto.dart` or `lib/features/monitoring/data/mappers/room_device_mapper.dart`, with Firebase path `child('rooms')` retained in `firebase_room_device_data_source.dart`.

- [ ] **Step 6: Check whitespace and worktree scope**

Run:

```powershell
git diff --check
git status --short
git diff --stat
```

Expected: no whitespace errors; only intended Plan 7 Dart/test files are changed by implementation. Existing unrelated Plan 1-6 modifications remain intact. No commit is created.

---

## State Transition Contract

Implementation must preserve this exact behavior:

```text
Initial room snapshot:
  confirmedDeviceData = snapshot
  deviceData = snapshot
  pendingDevices = {}
  commandErrors = {}

Optimistic command(address, desired):
  deviceData = deviceData.set(address, desired)
  confirmedDeviceData = unchanged
  pendingDevices += address
  commandErrors[address] removed

Command write success:
  pendingDevices remains until confirmed /rooms value matches

Confirmed /rooms update:
  confirmedDeviceData = new snapshot
  unrelated devices use new confirmed values immediately
  pending address keeps desired visible value while mismatch remains
  matching address removes pending and error and cancels timer

Write failure:
  pending address removed
  deviceData restored from latest confirmed snapshot
  other pending desired values reapplied
  commandErrors[address] = 'Perintah gagal dikirim'

Timeout:
  pending address removed
  deviceData restored from latest confirmed snapshot
  other pending desired values reapplied
  commandErrors[address] = 'Perintah tidak dikonfirmasi perangkat'
```

Presentation mapping must preserve this priority:

```text
errorMessage != null  = failed
isPending             = pending
value == null         = unknown
value.isOn == true    = on
value.isOn == false   = off
```

Control availability must preserve this rule:

```text
unknown + no value       = disabled
pending                  = disabled
failed + known value     = enabled
failed + no known value  = disabled
off/on                   = enabled
```

## Acceptance Criteria

- `RoomDeviceCollection`, `DeviceAddress`, dan `RoomDeviceValue` menggantikan raw room maps di repository, use case, BLoC state, event, dan UI.
- `DeviceAddress` equality/hashCode membuat pending dan error benar-benar device-specific.
- State-only bool menjadi typed value dengan `brightness == null`.
- Dimmable object mempertahankan non-null brightness, termasuk `0` saat off.
- Brightness numeric int/double/string menjadi integer clamped `0..100`.
- Null root, non-map root, non-map room, malformed device, invalid state, dan invalid brightness tidak dibuat menjadi OFF.
- Firebase data source return DTO; repository map DTO ke entity; only room mapper membaca node shape.
- Unknown tampil `Status belum tersedia`, icon `help_outline`, dan control disabled.
- Off tampil `Mati`, icon `power_off`, dan control enabled.
- On tampil `Nyala`, icon `power`, dan control enabled.
- Pending tampil `Menunggu konfirmasi`, compact progress indicator/`sync`, dan control terkait disabled.
- Failed menampilkan existing error text dan `error_outline`; control enabled bila confirmed value tersedia.
- Command A pending tidak memblokir command B.
- Confirmed update B tidak menghapus pending desired value A.
- Write failure dan timeout rollback ke latest confirmed snapshot.
- Firebase room path, command path, payload, timeout, rollback semantics, route, theme, labels, telemetry, history, dan cost/emission tetap kompatibel.
- No horizontal overflow pada `320px` dengan text scale `2x`.
- `flutter analyze`, `flutter test`, architecture tests, dan `flutter build apk --debug` lulus.

## Self-Review

- **Spec coverage:** domain entities/collection, DTO, mapper, repository/use case, typed BLoC transitions, view mapper, Monitoring UI, Control UI, accessibility, responsive behavior, architecture tests, regression tests, build, rollout, and rollback are mapped to Tasks 1-9.
- **Placeholder scan:** no `TBD`, `TODO`, or vague implementation-only step. Every production change names a file, interface, transition, or exact code replacement; every test task names command and expected result.
- **Type consistency:** `RoomDeviceCollectionDto` exists only at data boundary; repository/use case/BLoC use `RoomDeviceCollection`; BLoC keys use `DeviceAddress`; presentation mapper consumes the same entity and typed state collections.
- **Boundary consistency:** domain has no framework/data import; data source owns Firebase SDK; mapper owns room node parsing; presentation mapper imports domain only; screens import BLoC/domain/presentation and never parse Firebase maps.
- **Behavior consistency:** write success does not clear pending; only matching `/rooms` update clears pending; failure/timeout restore latest confirmed data; unrelated pending addresses survive unrelated confirmed updates.

## Approval Gate

Do not modify production code, tests, dependencies, routes, Firebase configuration, or build files until user explicitly approves execution of this plan.
