# Clean Architecture Boundary Tahap 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membuat boundary Clean Architecture awal tanpa mengubah Firebase path, payload command, raw device state, atau tampilan aplikasi.

**Architecture:** Repository contract pindah ke feature `domain` sementara `FirebaseService` tetap adapter Firebase tunggal. `AppDependencies` menjadi composition root dependency; root provider membuat `MonitoringBloc` dan `HistoryBloc`. Model chart history dipisah dari BLoC agar `history_state.dart` tidak mengimpor file implementasi BLoC.

**Tech Stack:** Flutter, Dart 3.8.1, flutter_bloc 9.1.1, Firebase Realtime Database, Cloud Firestore, flutter_test.

## Global Constraints

- Jangan ubah Firebase path: `device/sensorData`, `.info/connected`, `rooms`, `commands/rooms/<roomKey>/<deviceKey>`, atau `sensorLogs`.
- Jangan ubah format command state-only atau dimmable.
- Jangan ubah flow optimistic command, pending, timeout, rollback, atau confirmed state `/rooms`.
- Jangan memindahkan entity dari `lib/models/model.dart` pada tahap ini.
- Jangan tambah package dependency.
- Jangan mengubah Firebase rules, Firebase options, atau UI copy.
- Jangan commit tanpa instruksi eksplisit pengguna.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/features/monitoring/domain/repositories/monitoring_repository.dart` | Contract monitoring yang bebas Firebase dan Flutter. |
| `lib/features/history/domain/repositories/history_repository.dart` | Contract history yang bebas Firebase dan Flutter. |
| `lib/features/history/presentation/models/chart_point.dart` | Value model satu titik chart. |
| `lib/features/history/presentation/models/history_chart_data.dart` | Koleksi titik untuk enam seri chart. |
| `lib/app/app_dependencies.dart` | Holder dependency repository dan factory Firebase sementara. |
| `lib/services/firebase_service.dart` | Adapter Firebase yang implement contract domain. |
| `lib/bloc/monitoring/monitoring_bloc.dart` | Menggunakan contract monitoring domain. |
| `lib/bloc/history/history_bloc.dart` | Menggunakan contract history domain dan model chart terpisah. |
| `lib/bloc/history/history_state.dart` | Menggunakan model chart terpisah; tidak import BLoC. |
| `lib/main.dart` | Membuat `AppDependencies` setelah Firebase bootstrap dan memasang dua BLoC root. |
| `lib/screen/history.dart` | Mengonsumsi `HistoryBloc` root tanpa membuat Firebase service/BLoC. |
| `test/monitoring_bloc_test.dart` | Mengimpor contract monitoring baru. |
| `test/app_dependencies_test.dart` | Memverifikasi dependency holder memasok kedua contract ke BLoC. |
| `test/architecture_boundary_test.dart` | Menegakkan boundary import tahap 1. |

### Task 1: Repository Contract Domain

**Files:**
- Create: `lib/features/monitoring/domain/repositories/monitoring_repository.dart`
- Create: `lib/features/history/domain/repositories/history_repository.dart`
- Modify: `lib/services/firebase_service.dart:1-29`
- Modify: `lib/bloc/monitoring/monitoring_bloc.dart:1-18`
- Modify: `lib/bloc/history/history_bloc.dart:1-12`
- Modify: `test/monitoring_bloc_test.dart:1-10`
- Test: `test/architecture_boundary_test.dart`

**Consumes:** `McbDataCollection` dan `HistoricalMcbData` dari `lib/models/model.dart`.

**Produces:**

```dart
abstract interface class MonitoringRepository {
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

abstract interface class HistoryRepository {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}
```

- [ ] **Step 1: Write failing architecture test**

Create `test/architecture_boundary_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String relativePath) {
  return File(relativePath).readAsStringSync();
}

void main() {
  group('Clean Architecture boundary tahap 1', () {
    test('domain repository contracts avoid framework imports', () {
      const repositoryFiles = [
        'lib/features/monitoring/domain/repositories/monitoring_repository.dart',
        'lib/features/history/domain/repositories/history_repository.dart',
      ];
      const forbiddenImports = [
        'package:flutter/',
        'package:flutter_bloc/',
        'package:firebase_',
        'package:cloud_firestore/',
      ];

      for (final file in repositoryFiles) {
        final source = readProjectFile(file);
        for (final forbiddenImport in forbiddenImports) {
          expect(source, isNot(contains(forbiddenImport)), reason: file);
        }
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: FAIL because repository contract files do not exist.

- [ ] **Step 3: Create contracts and rewire imports**

Create `lib/features/monitoring/domain/repositories/monitoring_repository.dart`:

```dart
import 'package:esh/models/model.dart';

abstract interface class MonitoringRepository {
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
```

Create `lib/features/history/domain/repositories/history_repository.dart`:

```dart
import 'package:esh/models/model.dart';

abstract interface class HistoryRepository {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}
```

Replace repository declarations in `lib/services/firebase_service.dart` with imports:

```dart
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
```

Keep:

```dart
class FirebaseService implements MonitoringRepository, HistoryRepository {
```

Add matching domain repository imports to both BLoC files. Remove their `firebase_service.dart` imports. Update `test/monitoring_bloc_test.dart` to import `MonitoringRepository` from domain.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
flutter test test/architecture_boundary_test.dart test/monitoring_bloc_test.dart
```

Expected: PASS.

- [ ] **Step 5: Review intended diff**

Run:

```powershell
git diff -- lib/features lib/services/firebase_service.dart lib/bloc test/monitoring_bloc_test.dart test/architecture_boundary_test.dart
```

Expected: Contract declarations exist only under `features/*/domain/repositories`; Firebase behavior unchanged.

### Task 2: History Chart Presentation Models

**Files:**
- Create: `lib/features/history/presentation/models/chart_point.dart`
- Create: `lib/features/history/presentation/models/history_chart_data.dart`
- Modify: `lib/bloc/history/history_bloc.dart:1-5,214-249`
- Modify: `lib/bloc/history/history_state.dart:1-4`
- Modify: `test/architecture_boundary_test.dart`

**Consumes:** `HistoricalMcbData` from `lib/models/model.dart`.

**Produces:**

```dart
class ChartPoint {
  final double x;
  final double y;
  final String mcbName;
  final DateTime timestamp;
}

class HistoryChartData {
  final List<ChartPoint> voltageData;
  final List<ChartPoint> currentData;
  final List<ChartPoint> powerData;
  final List<ChartPoint> energyData;
  final List<ChartPoint> temperatureData;
  final List<ChartPoint> humidityData;
}
```

- [ ] **Step 1: Extend failing boundary test**

Add this test in `test/architecture_boundary_test.dart`:

```dart
test('history state avoids importing BLoC implementation', () {
  final source = readProjectFile('lib/bloc/history/history_state.dart');

  expect(source, isNot(contains("import 'history_bloc.dart';")));
  expect(
    source,
    contains(
      'package:esh/features/history/presentation/models/history_chart_data.dart',
    ),
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: FAIL because `history_state.dart` imports `history_bloc.dart`.

- [ ] **Step 3: Move chart types**

Create `lib/features/history/presentation/models/chart_point.dart`:

```dart
class ChartPoint {
  final double x;
  final double y;
  final String mcbName;
  final DateTime timestamp;

  ChartPoint({
    required this.x,
    required this.y,
    required this.mcbName,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'ChartPoint(x: $x, y: $y, mcbName: $mcbName, timestamp: $timestamp)';
  }
}
```

Create `lib/features/history/presentation/models/history_chart_data.dart`:

```dart
import 'package:esh/features/history/presentation/models/chart_point.dart';

class HistoryChartData {
  final List<ChartPoint> voltageData;
  final List<ChartPoint> currentData;
  final List<ChartPoint> powerData;
  final List<ChartPoint> energyData;
  final List<ChartPoint> temperatureData;
  final List<ChartPoint> humidityData;

  HistoryChartData({
    required this.voltageData,
    required this.currentData,
    required this.powerData,
    required this.energyData,
    required this.temperatureData,
    required this.humidityData,
  });
}
```

Import both presentation model files in `history_bloc.dart`. Remove local `HistoryChartData` and `ChartPoint` declarations. Replace `history_state.dart` import with:

```dart
import 'package:esh/features/history/presentation/models/history_chart_data.dart';
import 'package:esh/models/model.dart';
```

- [ ] **Step 4: Run focused test**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: PASS.

- [ ] **Step 5: Review intended diff**

Run:

```powershell
git diff -- lib/features/history/presentation/models lib/bloc/history test/architecture_boundary_test.dart
```

Expected: Chart filtering and tolerance code remain unchanged; only type locations/imports change.

### Task 3: Root Dependency Injection and History Provider

**Files:**
- Create: `lib/app/app_dependencies.dart`
- Modify: `lib/main.dart:1-111`
- Modify: `lib/screen/history.dart:1-21`
- Create: `test/app_dependencies_test.dart`
- Modify: `test/architecture_boundary_test.dart`

**Consumes:** Domain repository contracts, `FirebaseService`, `MonitoringBloc`, `HistoryBloc`.

**Produces:**

```dart
class AppDependencies {
  final MonitoringRepository monitoringRepository;
  final HistoryRepository historyRepository;

  const AppDependencies({
    required this.monitoringRepository,
    required this.historyRepository,
  });

  factory AppDependencies.firebase();
}
```

- [ ] **Step 1: Write failing app dependency test**

Create `test/app_dependencies_test.dart`:

```dart
import 'dart:async';

import 'package:esh/app/app_dependencies.dart';
import 'package:esh/bloc/history/history_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository implements MonitoringRepository, HistoryRepository {
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
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    return const [];
  }

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> getRoomDevicesStream() => const Stream.empty();
}

void main() {
  test('dependencies provide repository contracts to both BLoCs', () async {
    final repository = FakeRepository();
    final dependencies = AppDependencies(
      monitoringRepository: repository,
      historyRepository: repository,
    );
    final monitoringBloc = MonitoringBloc(
      firebaseService: dependencies.monitoringRepository,
    );
    final historyBloc = HistoryBloc(
      firebaseService: dependencies.historyRepository,
    );

    expect(monitoringBloc, isA<MonitoringBloc>());
    expect(historyBloc, isA<HistoryBloc>());

    await monitoringBloc.close();
    await historyBloc.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test test/app_dependencies_test.dart
```

Expected: FAIL because `lib/app/app_dependencies.dart` does not exist.

- [ ] **Step 3: Add dependency holder and root providers**

Create `lib/app/app_dependencies.dart`:

```dart
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/services/firebase_service.dart';

class AppDependencies {
  final MonitoringRepository monitoringRepository;
  final HistoryRepository historyRepository;

  const AppDependencies({
    required this.monitoringRepository,
    required this.historyRepository,
  });

  factory AppDependencies.firebase() {
    final firebaseService = FirebaseService();
    return AppDependencies(
      monitoringRepository: firebaseService,
      historyRepository: firebaseService,
    );
  }
}
```

In `main.dart`, import `AppDependencies`, `HistoryBloc`, and `MultiBlocProvider` dependencies. Change `EshApp` to receive `required this.dependencies`, then use:

```dart
return MultiBlocProvider(
  providers: [
    BlocProvider<MonitoringBloc>(
      create: (context) =>
          MonitoringBloc(firebaseService: dependencies.monitoringRepository)
            ..add(StartMonitoring()),
    ),
    BlocProvider<HistoryBloc>(
      create: (context) =>
          HistoryBloc(firebaseService: dependencies.historyRepository),
    ),
  ],
  child: MaterialApp.router(
    debugShowCheckedModeBanner: false,
    title: 'Monel Monitoring App',
    routerConfig: router,
  ),
);
```

After Firebase bootstrap success, return:

```dart
return EshApp(dependencies: AppDependencies.firebase());
```

In `screen/history.dart`, remove Firebase service import. Replace `History.build` body with:

```dart
return const HistoryView();
```

- [ ] **Step 4: Extend boundary test**

Add this test in `test/architecture_boundary_test.dart`:

```dart
test('history screen avoids concrete Firebase service', () {
  final source = readProjectFile('lib/screen/history.dart');

  expect(source, isNot(contains('services/firebase_service.dart')));
  expect(source, isNot(contains('FirebaseService(')));
  expect(source, isNot(contains('BlocProvider(')));
});
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
flutter test test/app_dependencies_test.dart test/architecture_boundary_test.dart test/widget_test.dart
```

Expected: PASS.

- [ ] **Step 6: Review intended diff**

Run:

```powershell
git diff -- lib/app lib/main.dart lib/screen/history.dart test/app_dependencies_test.dart test/architecture_boundary_test.dart
```

Expected: only root creates Firebase adapter and BLoCs; history page behavior unchanged.

### Task 4: Boundary Enforcement Completion

**Files:**
- Modify: `test/architecture_boundary_test.dart`
- Test: `test/architecture_boundary_test.dart`

**Consumes:** Final source paths from Tasks 1-3.

**Produces:** Tests blocking direct BLoC import of Firebase adapter and local history chart type declarations.

- [ ] **Step 1: Extend failing boundary test**

Add:

```dart
test('BLoCs depend on domain contracts instead of Firebase adapter', () {
  const blocFiles = [
    'lib/bloc/monitoring/monitoring_bloc.dart',
    'lib/bloc/history/history_bloc.dart',
  ];

  for (final file in blocFiles) {
    final source = readProjectFile(file);
    expect(source, isNot(contains('services/firebase_service.dart')), reason: file);
  }
});

test('history BLoC imports presentation chart models', () {
  final source = readProjectFile('lib/bloc/history/history_bloc.dart');

  expect(
    source,
    contains('features/history/presentation/models/chart_point.dart'),
  );
  expect(
    source,
    contains('features/history/presentation/models/history_chart_data.dart'),
  );
  expect(source, isNot(contains('class HistoryChartData')));
  expect(source, isNot(contains('class ChartPoint')));
});
```

- [ ] **Step 2: Run test**

Run:

```powershell
flutter test test/architecture_boundary_test.dart
```

Expected: PASS after Tasks 1-3.

- [ ] **Step 3: Check no forbidden imports remain**

Run:

```powershell
rg "services/firebase_service.dart" lib/bloc lib/screen
```

Expected: no match.

- [ ] **Step 4: Check public contract locations**

Run:

```powershell
rg "abstract (interface )?class (MonitoringRepository|HistoryRepository)" lib
```

Expected: exactly two matches in domain repository files.

### Task 5: Full Verification

**Files:**
- Modify only if formatter reports changes: affected `lib/` and `test/` Dart files.

- [ ] **Step 1: Run formatter check**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
```

Expected: exit code `0`.

If nonzero, run:

```powershell
dart format lib test
```

Then rerun check until exit code `0`.

- [ ] **Step 2: Run static analysis**

Run:

```powershell
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 3: Run all tests**

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

Expected: build succeeds and prints APK output path.

- [ ] **Step 5: Inspect final diff and status**

Run:

```powershell
git diff --check
git status --short
git diff --stat
```

Expected: no whitespace error; changes limited to planned Dart, test, and documentation files.

- [ ] **Step 6: Do not commit**

User has not requested a commit. Leave intended changes unstaged.

## Self-Review

- Scope coverage: contracts, chart import cycle, composition root, history screen dependency, and architecture tests map to approved spec.
- Placeholders: none.
- Interface consistency: `MonitoringRepository`, `HistoryRepository`, `AppDependencies`, `ChartPoint`, and `HistoryChartData` use one signature and path throughout plan.
- Scope boundary: data source split, entity extraction, use cases, typed device state, Firebase schema, and UI changes remain excluded.
