# Clean Architecture Use Case Plan 6 Design

## Goal

Memindahkan operasi aplikasi monitoring dan history dari BLoC ke use case kecil. BLoC hanya mengelola event, state, subscription lifecycle, optimistic state, pending confirmation, dan chart presentation. Repository contract menjadi dependency use case, bukan dependency BLoC.

## Scope

Plan 6 mencakup lima use case:

```text
WatchMonitoringDataUseCase
WatchConnectionStatusUseCase
WatchRoomDevicesUseCase
ControlRoomDeviceUseCase
LoadHistoryDataUseCase
```

Plan 6 mencakup:

- file use case domain;
- use case unit test dengan fake repository;
- BLoC constructor dan call-site memakai use case;
- `AppDependencies` membuat repository, use case, lalu BLoC root;
- test BLoC dan dependency wiring diubah untuk fake use case atau factory test helper.

Plan 6 tidak mencakup:

- cost/emission use case; tetap Plan 9;
- entity/device state typed; tetap Plan 7;
- perubahan repository contract, DTO, data source, Firebase path/query/payload;
- perubahan BLoC event/state, optimistic update, timeout, rollback, pending confirmation, history chart, error text, atau UI;
- perubahan class route/widget;
- dependency baru.

## Target Structure

```text
lib/features/
  monitoring/
    domain/
      repositories/
        monitoring_repository.dart
      usecases/
        watch_monitoring_data_use_case.dart
        watch_connection_status_use_case.dart
        watch_room_devices_use_case.dart
        control_room_device_use_case.dart
  history/
    domain/
      repositories/
        history_repository.dart
      usecases/
        load_history_data_use_case.dart
```

## Interfaces

### Monitoring use cases

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

Use case tidak import Flutter, Firebase, BLoC, DTO, data source, atau data repository implementation. `WatchRoomDevicesUseCase` tetap expose raw map sampai Plan 7 mengganti typed device state.

### History use case

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

## BLoC Changes

### `MonitoringBloc`

Ganti field:

```dart
final MonitoringRepository firebaseService;
```

Dengan:

```dart
final WatchMonitoringDataUseCase watchMonitoringData;
final WatchConnectionStatusUseCase watchConnectionStatus;
final WatchRoomDevicesUseCase watchRoomDevices;
final ControlRoomDeviceUseCase controlRoomDevice;
```

Mapping behavior wajib sama:

```text
firebaseService.getMonitoringDataStream()  -> watchMonitoringData()
firebaseService.getConnectionStatus()      -> watchConnectionStatus()
firebaseService.getRoomDevicesStream()     -> watchRoomDevices()
firebaseService.controlRoomDevice(...)     -> controlRoomDevice(...)
```

`brightness.toInt()` tetap terjadi di BLoC sebelum `ControlRoomDeviceUseCase`, karena BLoC event saat ini memakai `double` dan perubahan event scope Plan 7.

### `HistoryBloc`

Ganti:

```dart
final HistoryRepository firebaseService;
```

Dengan:

```dart
final LoadHistoryDataUseCase loadHistoryData;
```

Mapping behavior sama:

```text
firebaseService.getHistoricalData(...) -> loadHistoryData(...)
```

Request sequence, history empty/error state, chart processing, date range behavior, dan error text tidak berubah.

## App Dependencies

`AppDependencies` tetap menyimpan repository contract karena test factory dan next plan masih memerlukannya. Tambah method factory pembuat BLoC agar root tidak tahu use case detail:

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

`main.dart` memakai:

```dart
create: (context) => dependencies.createMonitoringBloc()..add(StartMonitoring())
create: (context) => dependencies.createHistoryBloc()
```

No Firebase instance dibuat sebelum `FirebaseBootstrap` berhasil karena `AppDependencies.firebase()` tetap hanya dipanggil setelah initialization success.

## Testing

### Use case unit tests

Fake monitoring repository membuktikan empat use case meneruskan stream dan command parameter sama. Fake history repository membuktikan date/limit sama.

### BLoC tests

`MonitoringBloc` test menerima use case nyata dengan fake repository. Ini menjaga test behavior saat ini sambil memastikan BLoC tidak lagi import repository contract.

Tambahkan architecture test:

- MonitoringBloc tidak import `monitoring_repository.dart`.
- HistoryBloc tidak import `history_repository.dart`.
- setiap use case import repository contract dan entity yang dipakai saja.
- use case tidak import `data/`, Firebase, Flutter, BLoC, atau DTO.

### Behavior regression

Pertahankan:

- start monitoring idempotent;
- matching room update confirms pending command;
- write failure rollback;
- repository DTO-to-entity mapping;
- history date query limit;
- widget layout test.

## Acceptance Criteria

- Lima use case ada pada domain feature.
- BLoC tidak import repository contract.
- BLoC tidak menyimpan field repository bernama `firebaseService`.
- Use case hanya depend domain repository/entity/Dart.
- `AppDependencies` membuat use case dan BLoC root.
- Stream, command parameter, error text, timeout, pending confirmation, history query, chart, route, dan UI behavior tidak berubah.
- Cost/emission tetap ada di UI sampai Plan 9.
- `flutter analyze`, `flutter test`, `flutter build apk --debug`, formatter scope, architecture test lulus.

## Next Plan

Plan 7 mengganti raw `Map<String, dynamic>` device state dengan entity typed. Plan 9 memindahkan cost/emission business rule dari `monitoring.dart` ke domain use case.
