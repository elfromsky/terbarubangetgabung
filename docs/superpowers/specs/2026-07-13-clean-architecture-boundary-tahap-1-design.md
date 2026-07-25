# Clean Architecture Boundary Tahap 1 Design

## Goal

Membangun boundary Clean Architecture awal tanpa mengubah Firebase path, format command, raw device state, atau behavior UI saat ini.

## Scope

Tahap ini mencakup:

- memindahkan repository contract ke domain feature;
- mendaftarkan `MonitoringBloc` dan `HistoryBloc` dari composition root;
- menghapus pembuatan `FirebaseService()` dari `screen/history.dart`;
- memisahkan `HistoryChartData` dan `ChartPoint` dari implementasi `HistoryBloc`;
- menambah test batas import yang melindungi perubahan ini.

Tahap ini tidak mencakup:

- pemecahan `FirebaseService` menjadi data source/repository implementation;
- pemindahan entity dari `lib/models/model.dart`;
- use case;
- typed device state;
- perubahan Firebase schema atau Firebase rules;
- perubahan flow optimistic command, pending, rollback, atau confirmation `/rooms`;
- perubahan tampilan UI.

## Target Struktur

```text
lib/
  app/
    app_dependencies.dart
  features/
    history/
      domain/
        repositories/
          history_repository.dart
      presentation/
        models/
          chart_point.dart
          history_chart_data.dart
    monitoring/
      domain/
        repositories/
          monitoring_repository.dart
  bloc/
  models/
  routes/
  screen/
  services/
  widgets/
```

Folder lama tetap ada pada tahap ini. BLoC dan screen belum dipindahkan agar perubahan kecil, mudah diverifikasi, dan tidak mengubah route atau widget tree lebih dari provider root.

## Dependency Direction

```text
main.dart
  imports app/app_dependencies.dart
  imports BLoC, event, router, Flutter

app/app_dependencies.dart
  imports FirebaseService dan repository contract domain

BLoC
  imports repository contract domain
  imports model lama dan flutter_bloc

FirebaseService
  imports repository contract domain
  imports Firebase SDK dan model lama

screen/history.dart
  imports HistoryBloc, HistoryEvent, HistoryState, Flutter
  tidak import FirebaseService
```

`FirebaseService` menjadi adapter sementara. Class ini tetap mengimplementasikan dua contract domain sampai tahap pemecahan data layer berikutnya.

## Repository Contract

`MonitoringRepository` pindah ke:

```text
lib/features/monitoring/domain/repositories/monitoring_repository.dart
```

Contract mempertahankan signature saat ini agar behavior monitoring tidak berubah:

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
```

`HistoryRepository` pindah ke:

```text
lib/features/history/domain/repositories/history_repository.dart
```

```dart
abstract interface class HistoryRepository {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}
```

Contract memakai model lama pada tahap ini. Entity domain murni ditunda sampai mapper Firebase dan repository implementation tersedia, sehingga tidak muncul dual model tanpa nilai fungsional.

## Composition Root

`AppDependencies` menjadi class immutable untuk dependency aplikasi:

```dart
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

`EshApp` menerima `AppDependencies`. Root memasang `MultiBlocProvider`:

```text
MonitoringBloc memakai monitoringRepository dan menambah StartMonitoring.
HistoryBloc memakai historyRepository.
```

`History` hanya mengembalikan `HistoryView`. Route tetap membuat `const History()` dan menemukan `HistoryBloc` dari provider root.

Satu `FirebaseService` dipakai oleh dua repository interface seperti behavior lama. Tidak ada Firebase service yang dibuat sebelum Firebase initialization berhasil karena `EshApp` hanya dibuat setelah `FirebaseBootstrap` sukses.

## History Chart Model

Pindahkan jenis data chart ke:

```text
lib/features/history/presentation/models/chart_point.dart
lib/features/history/presentation/models/history_chart_data.dart
```

`history_bloc.dart` dan `history_state.dart` mengimpor file model ini. `history_state.dart` tidak lagi mengimpor `history_bloc.dart`, sehingga import cycle hilang.

Chart filtering, tolerance, data ordering, dan output chart tidak berubah.

## Test Strategy

Pertahankan `test/monitoring_bloc_test.dart` dengan import contract baru.

Tambah `test/architecture_boundary_test.dart` yang memindai file source berikut:

- domain repository tidak mengimpor Flutter, Firebase, atau BLoC;
- BLoC tidak mengimpor `services/firebase_service.dart`;
- `screen/history.dart` tidak mengimpor `services/firebase_service.dart`;
- `history_state.dart` tidak mengimpor `history_bloc.dart`.

Tambah `test/app_dependencies_test.dart` untuk memverifikasi satu `AppDependencies` bisa membuat `MonitoringBloc` dan `HistoryBloc` dengan fake repository. Test tidak memanggil Firebase SDK.

## Error Handling

Tidak ubah behavior error data atau UI pada tahap ini.

- Firebase initialization failure tetap ditangani `FirebaseBootstrap`.
- `FirebaseService` tetap meneruskan exception seperti sekarang.
- BLoC tetap memetakan error menjadi state saat ini.
- Tidak ada perubahan error contract untuk command atau history.

## Acceptance Criteria

- `MonitoringRepository` dan `HistoryRepository` tidak lagi dideklarasikan di `lib/services/firebase_service.dart`.
- `FirebaseService` mengimplementasikan contract dari `features/*/domain/repositories`.
- `MonitoringBloc` dan `HistoryBloc` tidak import `firebase_service.dart`.
- `History` tidak membuat `FirebaseService` atau `HistoryBloc`.
- `HistoryChartData` dan `ChartPoint` tidak berada di `history_bloc.dart`.
- `history_state.dart` tidak import `history_bloc.dart`.
- Firebase path dan payload command tidak berubah.
- `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, dan `flutter build apk --debug` lulus.

## Next Migration

Setelah tahap ini stabil, tahap 2 memisahkan `FirebaseService` menjadi data source Firebase dan repository implementation. Tahap tersebut juga memindahkan mapper Firestore/Realtime Database dari entity/model lama ke data layer.
