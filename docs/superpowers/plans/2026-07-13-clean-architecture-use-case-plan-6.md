# Clean Architecture Use Case Plan 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Buat lima use case domain agar `MonitoringBloc` dan `HistoryBloc` tidak lagi bergantung langsung pada repository contract.

**Architecture:** Use case kecil mendelegasikan operasi ke repository contract domain. BLoC mengelola lifecycle stream, state, optimistic command, timeout, confirmation, dan chart; use case menghubungkan BLoC ke operasi aplikasi. `AppDependencies` menyusun repository lalu use case lalu BLoC.

**Tech Stack:** Flutter, Dart 3.8.1, flutter_bloc 9.1.1, firebase_database 10.5.0, cloud_firestore 4.15.0, flutter_test.

## Global Constraints

- Jangan ubah Firebase path, collection, query, DTO, repository contract, command payload, BLoC event/state, optimistic update, timeout, rollback, confirmation, history chart, route, atau UI.
- Jangan buat cost/emission use case. Cost/emission tetap di `lib/screen/monitoring.dart` sampai Plan 9.
- Jangan ganti raw room-device `Map`; typed device state tetap Plan 7.
- Use case hanya import domain repository/entity dan Dart core.
- BLoC tidak import repository contract setelah migration selesai.
- Jangan tambah dependency atau commit.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart` | Stream telemetry entity. |
| `lib/features/monitoring/domain/usecases/watch_connection_status_use_case.dart` | Stream Firebase connection state. |
| `lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart` | Stream raw room map sementara. |
| `lib/features/monitoring/domain/usecases/control_room_device_use_case.dart` | Forward command device canonical. |
| `lib/features/history/domain/usecases/load_history_data_use_case.dart` | Load history date range dan limit. |
| `test/use_case_test.dart` | Delegasi parameter/stream semua use case. |
| `lib/bloc/monitoring/monitoring_bloc.dart` | Gunakan empat monitoring use case. |
| `lib/bloc/history/history_bloc.dart` | Gunakan history use case. |
| `lib/app/app_dependencies.dart` | Buat use case dan BLoC factory. |
| `test/architecture_boundary_test.dart` | Larang repository import dari BLoC dan framework/data import dari use case. |

### Task 1: Monitoring Use Cases

**Files:**
- Create: `lib/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart`
- Create: `lib/features/monitoring/domain/usecases/watch_connection_status_use_case.dart`
- Create: `lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart`
- Create: `lib/features/monitoring/domain/usecases/control_room_device_use_case.dart`
- Create: `test/use_case_test.dart`

**Interfaces:**

```dart
class WatchMonitoringDataUseCase {
  final MonitoringRepository repository;

  WatchMonitoringDataUseCase({required this.repository});

  Stream<McbDataCollection> call();
}

class WatchConnectionStatusUseCase {
  final MonitoringRepository repository;

  WatchConnectionStatusUseCase({required this.repository});

  Stream<bool> call();
}

class WatchRoomDevicesUseCase {
  final MonitoringRepository repository;

  WatchRoomDevicesUseCase({required this.repository});

  Stream<Map<String, dynamic>> call();
}

class ControlRoomDeviceUseCase {
  final MonitoringRepository repository;

  ControlRoomDeviceUseCase({required this.repository});

  Future<void> call({
    required String roomKey,
    required String deviceKey,
    required bool isOn,
    required int brightness,
    required bool supportsBrightness,
  });
}
```

- [ ] **Step 1: Write failing monitoring use-case tests**

Create `test/use_case_test.dart`:

```dart
import 'dart:async';

import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonitoringRepository implements MonitoringRepository {
  final monitoringController = StreamController<McbDataCollection>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
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
  Stream<bool> getConnectionStatus() => connectionController.stream;

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => monitoringController.stream;

  @override
  Stream<Map<String, dynamic>> getRoomDevicesStream() => roomController.stream;

  Future<void> close() async {
    await monitoringController.close();
    await connectionController.close();
    await roomController.close();
  }
}

class FakeHistoryRepository implements HistoryRepository {
  DateTime? startDate;
  DateTime? endDate;
  int? limit;

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    this.startDate = startDate;
    this.endDate = endDate;
    this.limit = limit;
    return const [];
  }
}

void main() {
  late FakeMonitoringRepository monitoringRepository;

  setUp(() {
    monitoringRepository = FakeMonitoringRepository();
  });

  tearDown(() => monitoringRepository.close());

  test('monitoring stream use cases return repository streams', () async {
    final telemetry = WatchMonitoringDataUseCase(
      repository: monitoringRepository,
    );
    final connection = WatchConnectionStatusUseCase(
      repository: monitoringRepository,
    );
    final rooms = WatchRoomDevicesUseCase(repository: monitoringRepository);

    expect(telemetry(), same(monitoringRepository.monitoringController.stream));
    expect(connection(), same(monitoringRepository.connectionController.stream));
    expect(rooms(), same(monitoringRepository.roomController.stream));
  });

  test('control room device use case forwards canonical parameters', () async {
    final useCase = ControlRoomDeviceUseCase(repository: monitoringRepository);

    await useCase(
      roomKey: 'dapur',
      deviceKey: 'lampu',
      isOn: true,
      brightness: 75,
      supportsBrightness: true,
    );

    expect(
      monitoringRepository.command,
      ['dapur', 'lampu', true, 75, true],
    );
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/use_case_test.dart
```

Expected: FAIL because use case files do not exist.

- [ ] **Step 3: Create monitoring use cases**

Create `watch_monitoring_data_use_case.dart`:

```dart
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchMonitoringDataUseCase {
  final MonitoringRepository repository;

  WatchMonitoringDataUseCase({required this.repository});

  Stream<McbDataCollection> call() {
    return repository.getMonitoringDataStream();
  }
}
```

Create `watch_connection_status_use_case.dart`:

```dart
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchConnectionStatusUseCase {
  final MonitoringRepository repository;

  WatchConnectionStatusUseCase({required this.repository});

  Stream<bool> call() {
    return repository.getConnectionStatus();
  }
}
```

Create `watch_room_devices_use_case.dart`:

```dart
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchRoomDevicesUseCase {
  final MonitoringRepository repository;

  WatchRoomDevicesUseCase({required this.repository});

  Stream<Map<String, dynamic>> call() {
    return repository.getRoomDevicesStream();
  }
}
```

Create `control_room_device_use_case.dart`:

```dart
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class ControlRoomDeviceUseCase {
  final MonitoringRepository repository;

  ControlRoomDeviceUseCase({required this.repository});

  Future<void> call({
    required String roomKey,
    required String deviceKey,
    required bool isOn,
    required int brightness,
    required bool supportsBrightness,
  }) {
    return repository.controlRoomDevice(
      roomKey,
      deviceKey,
      isOn,
      brightness,
      supportsBrightness,
    );
  }
}
```

- [ ] **Step 4: Run focused test**

Run:

```powershell
flutter test test/use_case_test.dart
```

Expected: monitoring tests PASS; history import remains unused until Task 2, so remove unused history imports/classes temporarily if analyzer rejects them.

- [ ] **Step 5: Check use-case boundary**

Run project content search for `data/`, `firebase`, `flutter`, `bloc`, and `Dto` inside `lib/features/monitoring/domain/usecases`.

Expected: no match.

### Task 2: History Use Case

**Files:**
- Create: `lib/features/history/domain/usecases/load_history_data_use_case.dart`
- Modify: `test/use_case_test.dart`

**Interfaces:**

```dart
class LoadHistoryDataUseCase {
  final HistoryRepository repository;

  LoadHistoryDataUseCase({required this.repository});

  Future<List<HistoricalMcbData>> call({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}
```

- [ ] **Step 1: Add failing history use-case test**

Add imports:

```dart
import 'package:esh/features/history/domain/usecases/load_history_data_use_case.dart';
```

Add test:

```dart
test('load history use case forwards date range and limit', () async {
  final repository = FakeHistoryRepository();
  final useCase = LoadHistoryDataUseCase(repository: repository);
  final startDate = DateTime(2026, 7, 1);
  final endDate = DateTime(2026, 7, 2);

  final result = await useCase(
    startDate: startDate,
    endDate: endDate,
    limit: 200,
  );

  expect(result, isEmpty);
  expect(repository.startDate, startDate);
  expect(repository.endDate, endDate);
  expect(repository.limit, 200);
});
```

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/use_case_test.dart
```

Expected: FAIL because `LoadHistoryDataUseCase` does not exist.

- [ ] **Step 3: Create history use case**

Create `load_history_data_use_case.dart`:

```dart
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';

class LoadHistoryDataUseCase {
  final HistoryRepository repository;

  LoadHistoryDataUseCase({required this.repository});

  Future<List<HistoricalMcbData>> call({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) {
    return repository.getHistoricalData(
      startDate: startDate,
      endDate: endDate,
      limit: limit,
    );
  }
}
```

- [ ] **Step 4: Run focused test**

Run:

```powershell
flutter test test/use_case_test.dart
```

Expected: all use-case tests PASS.

### Task 3: BLoC Dependency Migration

**Files:**
- Modify: `lib/bloc/monitoring/monitoring_bloc.dart:1-145`
- Modify: `lib/bloc/history/history_bloc.dart:1-56`
- Modify: `test/monitoring_bloc_test.dart`

**Consumes:** Five use case classes from Tasks 1-2.

- [ ] **Step 1: Update failing BLoC constructor tests**

In `test/monitoring_bloc_test.dart`, import four monitoring use cases. Add helper:

```dart
MonitoringBloc createMonitoringBloc(FakeMonitoringRepository repository) {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(repository: repository),
    watchConnectionStatus: WatchConnectionStatusUseCase(
      repository: repository,
    ),
    watchRoomDevices: WatchRoomDevicesUseCase(repository: repository),
    controlRoomDevice: ControlRoomDeviceUseCase(repository: repository),
  );
}
```

Replace:

```dart
bloc = MonitoringBloc(firebaseService: repository);
```

With:

```dart
bloc = createMonitoringBloc(repository);
```

- [ ] **Step 2: Run BLoC test to verify failure**

Run:

```powershell
flutter test test/monitoring_bloc_test.dart
```

Expected: FAIL because constructor still requires `firebaseService`.

- [ ] **Step 3: Migrate `MonitoringBloc`**

Replace repository import with:

```dart
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
```

Replace field and constructor:

```dart
final WatchMonitoringDataUseCase watchMonitoringData;
final WatchConnectionStatusUseCase watchConnectionStatus;
final WatchRoomDevicesUseCase watchRoomDevices;
final ControlRoomDeviceUseCase controlRoomDevice;

MonitoringBloc({
  required this.watchMonitoringData,
  required this.watchConnectionStatus,
  required this.watchRoomDevices,
  required this.controlRoomDevice,
}) : super(MonitoringInitial()) {
```

Replace exact repository calls:

```dart
await controlRoomDevice(
  roomKey: event.roomKey,
  deviceKey: event.deviceKey,
  isOn: event.isOn,
  brightness: event.brightness.toInt(),
  supportsBrightness: event.supportsBrightness,
);

_dataSubscription = watchMonitoringData().listen(...);
_connectionSubscription = watchConnectionStatus().listen(...);
_deviceDataSubscription = watchRoomDevices().listen(...);
```

Do not modify any handlers, map manipulation, error text, timer, or lifecycle code.

- [ ] **Step 4: Migrate `HistoryBloc`**

Replace repository import with:

```dart
import 'package:esh/features/history/domain/usecases/load_history_data_use_case.dart';
```

Replace field and constructor:

```dart
final LoadHistoryDataUseCase loadHistoryData;

HistoryBloc({required this.loadHistoryData}) : super(HistoryInitial()) {
```

Replace:

```dart
final rawData = await firebaseService.getHistoricalData(
```

With:

```dart
final rawData = await loadHistoryData(
```

Leave request sequence, cast, chart processing, and error text unchanged.

- [ ] **Step 5: Run BLoC tests**

Run:

```powershell
flutter test test/monitoring_bloc_test.dart
```

Expected: PASS.

### Task 4: Dependency Injection and Architecture Tests

**Files:**
- Modify: `lib/app/app_dependencies.dart`
- Modify: `lib/main.dart`
- Modify: `test/app_dependencies_test.dart`
- Modify: `test/architecture_boundary_test.dart`

- [ ] **Step 1: Add failing dependency factory test**

In `test/app_dependencies_test.dart`, replace manual BLoC constructors with:

```dart
final monitoringBloc = dependencies.createMonitoringBloc();
final historyBloc = dependencies.createHistoryBloc();
```

Keep type assertions and close both BLoCs.

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
flutter test test/app_dependencies_test.dart
```

Expected: FAIL because factory methods do not exist.

- [ ] **Step 3: Add BLoC factories to `AppDependencies`**

Add imports:

```dart
import 'package:esh/bloc/history/history_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/features/history/domain/usecases/load_history_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
```

Add methods:

```dart
MonitoringBloc createMonitoringBloc() {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(
      repository: monitoringRepository,
    ),
    watchConnectionStatus: WatchConnectionStatusUseCase(
      repository: monitoringRepository,
    ),
    watchRoomDevices: WatchRoomDevicesUseCase(
      repository: monitoringRepository,
    ),
    controlRoomDevice: ControlRoomDeviceUseCase(
      repository: monitoringRepository,
    ),
  );
}

HistoryBloc createHistoryBloc() {
  return HistoryBloc(
    loadHistoryData: LoadHistoryDataUseCase(
      repository: historyRepository,
    ),
  );
}
```

- [ ] **Step 4: Simplify root BLoC providers**

In `main.dart`, replace BLoC construction only:

```dart
create: (context) => dependencies.createMonitoringBloc()
  ..add(StartMonitoring()),
```

```dart
create: (context) => dependencies.createHistoryBloc(),
```

Do not move Firebase bootstrap or alter MaterialApp/router.

- [ ] **Step 5: Add architecture tests**

Add to `test/architecture_boundary_test.dart`:

```dart
test('BLoCs depend on use cases instead of repository contracts', () {
  const blocFiles = [
    'lib/bloc/monitoring/monitoring_bloc.dart',
    'lib/bloc/history/history_bloc.dart',
  ];

  for (final file in blocFiles) {
    final source = readProjectFile(file);
    expect(source, isNot(contains('/domain/repositories/')), reason: file);
    expect(source, contains('/domain/usecases/'), reason: file);
  }
});

test('use cases avoid data, framework, DTO, and BLoC imports', () {
  const useCaseFiles = [
    'lib/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart',
    'lib/features/monitoring/domain/usecases/watch_connection_status_use_case.dart',
    'lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart',
    'lib/features/monitoring/domain/usecases/control_room_device_use_case.dart',
    'lib/features/history/domain/usecases/load_history_data_use_case.dart',
  ];
  const forbiddenTokens = [
    '/data/',
    'package:flutter',
    'package:firebase_',
    'package:cloud_firestore/',
    'flutter_bloc',
    'Dto',
  ];

  for (final file in useCaseFiles) {
    final source = readProjectFile(file);
    for (final token in forbiddenTokens) {
      expect(source, isNot(contains(token)), reason: file);
    }
  }
});
```

- [ ] **Step 6: Run dependency and boundary tests**

Run:

```powershell
flutter test test/app_dependencies_test.dart test/architecture_boundary_test.dart test/monitoring_bloc_test.dart test/use_case_test.dart
```

Expected: PASS.

### Task 5: Full Verification

- [ ] **Step 1: Format changed scope**

Run global check:

```powershell
dart format --output=none --set-exit-if-changed lib test
```

If only `lib/firebase_options.dart` fails, leave it unchanged. Format only Plan 6 Dart/test files, then rerun scope format check.

- [ ] **Step 2: Analyze**

```powershell
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 3: Full tests**

```powershell
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Build debug APK**

```powershell
flutter build apk --debug
```

Expected: `build\app\outputs\flutter-apk\app-debug.apk` exists.

- [ ] **Step 5: Final scope audit**

Run content searches proving:

```text
BLoC files contain no /domain/repositories/
Use cases contain no /data/, Firebase, Flutter, BLoC, or Dto
```

Then run:

```powershell
git diff --check
git status --short
git diff --stat
```

Expected: no whitespace error; intended Step 1-6 files only; no commit.

## Self-Review

- Coverage: five use cases, BLoC migration, AppDependencies factory, root provider, unit/BLoC/boundary tests, verification included.
- Type consistency: use case signatures match repository and BLoC calls exactly.
- Scope: cost/emission, typed device map, Firebase path/query/payload, BLoC behavior, and UI excluded.
- No placeholders: every task has paths, interfaces, tests, and commands.
