# Review Clean Architecture Flutter

## Ringkasan

Status proyek saat ini: **belum mengikuti Clean Architecture Flutter secara penuh**.

Arsitektur aktif lebih tepat disebut arsitektur sederhana berbasis BLoC:

```text
UI / Screen / Widget
  -> BLoC
  -> FirebaseService
  -> Firebase Realtime Database / Firestore
```

Struktur ini sudah lebih baik daripada UI langsung memanggil Firebase di semua tempat, tetapi belum punya pemisahan layer yang kuat seperti `presentation`, `domain`, `data`, `usecase`, `repository contract`, dan `repository implementation`.

## Kriteria Clean Architecture Flutter

Clean Architecture Flutter umumnya punya arah dependensi seperti ini:

```text
presentation
  -> domain

data
  -> domain

app / dependency injection
  -> presentation + domain + data
```

Aturan utamanya:

- `domain` tidak boleh import Flutter, Firebase, BLoC, UI, atau package data source.
- `presentation` boleh tahu BLoC/state/widget, tetapi tidak boleh membuat service Firebase konkret.
- `data` boleh tahu Firebase/API/local DB, tetapi harus implement contract dari `domain`.
- BLoC sebaiknya memanggil use case, bukan langsung memproses detail Firebase schema.
- Model domain harus murni, sedangkan parsing Firestore/Realtime Database tinggal di data layer.

## Struktur Saat Ini

Struktur utama di `lib/`:

```text
lib/
  bloc/
    history/
    monitoring/
  models/
  routes/
  screen/
  services/
  widgets/
  main.dart
  firebase_options.dart
```

Mapping layer saat ini:

| Folder | Peran sekarang | Catatan |
| --- | --- | --- |
| `lib/screen` | UI / halaman | Termasuk parsing raw device map di beberapa screen. |
| `lib/widgets` | Widget reusable | Masih presentation layer. |
| `lib/bloc` | State management | BLoC masih import repository dari file service konkret. |
| `lib/models` | Model data campuran | Berisi entity, mapper, dan serializer sekaligus. |
| `lib/services` | Firebase service + contract repository | Contract dan implementation berada di file sama. |
| `lib/routes` | Routing | Masih wajar sebagai app/presentation concern. |

## Temuan Utama

### 1. Belum Ada Layer `domain`, `data`, dan `presentation`

File yang menunjukkan struktur saat ini:

- `lib/bloc/monitoring/monitoring_bloc.dart`
- `lib/bloc/history/history_bloc.dart`
- `lib/models/model.dart`
- `lib/services/firebase_service.dart`
- `lib/screen/monitoring.dart`
- `lib/screen/control.dart`
- `lib/screen/history.dart`

Belum ada struktur seperti:

```text
features/monitoring/domain
features/monitoring/data
features/monitoring/presentation
features/history/domain
features/history/data
features/history/presentation
```

Dampak:

- Sulit memastikan arah dependensi benar.
- Business logic, mapping Firebase, dan UI state saling bercampur.
- Perubahan schema Firebase bisa berdampak ke BLoC dan screen.

### 2. `FirebaseService` Terlalu Banyak Tanggung Jawab

File: `lib/services/firebase_service.dart`

`FirebaseService` saat ini menangani:

- stream telemetry Realtime Database;
- stream status perangkat `rooms`;
- status koneksi `.info/connected`;
- command write ke `commands/rooms/...`;
- query Firestore `sensorLogs`;
- legacy query `energyData`;
- parsing timestamp;
- mapping `Map<dynamic, dynamic>` ke `Map<String, dynamic>`;
- save history;
- debug Firestore.

Dampak:

- Sulit dites secara terpisah.
- Sulit mengganti data source.
- Satu file data layer menjadi terlalu besar dan rentan berubah untuk banyak alasan.

### 3. Contract Repository Masih Berada di File Infrastructure

File: `lib/services/firebase_service.dart`

Saat ini interface berikut berada di file yang sama dengan implementasi Firebase:

```dart
abstract class MonitoringRepository { ... }
abstract class HistoryRepository { ... }
class FirebaseService implements MonitoringRepository, HistoryRepository { ... }
```

Ini sudah memakai dependency inversion sebagian, tetapi belum clean karena BLoC tetap import file service yang juga import Firebase SDK.

Target yang lebih bersih:

```text
domain/repositories/monitoring_repository.dart
domain/repositories/history_repository.dart
data/repositories/firebase_monitoring_repository.dart
data/repositories/firebase_history_repository.dart
```

### 4. Screen Masih Membuat Service Firebase Konkret

File: `lib/screen/history.dart`

Saat ini:

```dart
BlocProvider(
  create: (context) => HistoryBloc(firebaseService: FirebaseService()),
  child: const HistoryView(),
)
```

Masalah:

- Presentation layer tahu implementasi data layer.
- `History` sulit dites tanpa Firebase.
- Dependency injection tidak konsisten karena `MonitoringBloc` dibuat di `main.dart`, sedangkan `HistoryBloc` dibuat di screen.

Target:

```text
main.dart / app/di.dart
  -> membuat Firebase data source
  -> membuat repository implementation
  -> membuat use case
  -> membuat BLoC
  -> provide ke page
```

### 5. Model Domain Bercampur Dengan Mapping Firestore

File: `lib/models/model.dart`

Contoh:

```dart
factory HistoricalMcbData.fromFirestore(...)
Map<String, dynamic> toFirestore()
```

Masalah:

- Entity domain mengetahui format Firestore.
- Parsing error fallback ke `DateTime.now()` dapat menyamarkan data rusak.
- Domain jadi sulit dipakai ulang tanpa Firebase.

Target:

```text
domain/entities/historical_mcb_data.dart
data/models/historical_mcb_data_model.dart
data/mappers/historical_mcb_data_mapper.dart
```

### 6. Raw Firebase Map Bocor ke BLoC dan UI

File terkait:

- `lib/bloc/monitoring/monitoring_state.dart`
- `lib/bloc/monitoring/monitoring_event.dart`
- `lib/bloc/monitoring/monitoring_bloc.dart`
- `lib/screen/monitoring.dart`
- `lib/screen/control.dart`

Contoh state:

```dart
final Map<String, dynamic> deviceData;
final Map<String, dynamic> confirmedDeviceData;
```

UI juga membaca path seperti:

```dart
dbData['rooms']?[roomConfig.roomKey]?[device.deviceKey]
```

Masalah:

- UI tahu schema Firebase `rooms`.
- BLoC tahu detail node `state` dan `brightness`.
- Jika Firebase schema berubah, BLoC dan beberapa screen ikut berubah.
- `unknown` sering berubah menjadi default `false`, sehingga perangkat bisa terlihat OFF padahal data belum tersedia.

Target:

```text
RoomDeviceState
RoomDeviceCollection
DeviceCommand
ConfirmedDeviceState
PendingDeviceCommand
```

### 7. Business Rule Masih Ada di UI

File: `lib/screen/monitoring.dart`

Contoh:

```dart
const double electricityRate = 1699.53;
const double emissionFactor = 0.85;
final double totalEstimatedCost = state.mcbData.mcb1.energy * electricityRate;
final double totalEstimatedEmissions = state.mcbData.mcb1.energy * emissionFactor;
```

Masalah:

- Tarif listrik dan faktor emisi adalah policy aplikasi, bukan tanggung jawab widget.
- Sulit dites tanpa widget test.

Target:

```text
domain/usecases/estimate_energy_cost.dart
domain/usecases/estimate_emission.dart
presentation/mappers/monitoring_view_model_mapper.dart
```

### 8. `HistoryBloc` Memiliki Model Chart dan Ada Import Cycle

File terkait:

- `lib/bloc/history/history_bloc.dart`
- `lib/bloc/history/history_state.dart`

`HistoryChartData` dan `ChartPoint` berada di `history_bloc.dart`, lalu `history_state.dart` import `history_bloc.dart`.

Masalah:

- State bergantung pada file BLoC implementation.
- Import cycle membuat struktur rapuh.
- Model chart lebih cocok di presentation model terpisah.

Target:

```text
features/history/presentation/models/history_chart_data.dart
features/history/presentation/models/chart_point.dart
```

### 9. Analyzer Belum Menegakkan Boundary Arsitektur

File: `analysis_options.yaml`

Saat ini hanya memakai default Flutter lints:

```yaml
include: package:flutter_lints/flutter.yaml
```

Belum ada aturan yang mencegah:

- `presentation` import `data`;
- `domain` import Firebase;
- `domain` import Flutter;
- BLoC import service konkret;
- cyclic dependency antar layer.

Target:

- tambah architecture test yang scan import;
- atau tambah custom lint/import restriction;
- atau split package untuk boundary lebih keras.

## Hal Yang Sudah Baik

Proyek tidak sepenuhnya buruk. Beberapa fondasi sudah bisa dipakai untuk migrasi:

- BLoC sudah dipakai untuk monitoring dan history.
- Repository abstraction sudah ada meskipun lokasi belum tepat.
- Firebase access relatif terkonsentrasi di `FirebaseService`.
- `main.dart` sudah menjadi composition root sebagian untuk `MonitoringBloc`.
- Test `monitoring_bloc_test.dart` sudah memakai fake repository.
- README dan docs sudah mendokumentasikan path Firebase serta kontrak command/confirmed state.
- Model utama memakai immutable field, sehingga mudah diekstrak menjadi entity domain.

## Target Struktur Clean Architecture

Rekomendasi struktur feature-first:

```text
lib/
  app/
    di.dart
    router.dart
    app.dart

  core/
    error/
      failure.dart
    result/
      result.dart
    logging/

  features/
    monitoring/
      domain/
        entities/
          sensor_data.dart
          mcb_data.dart
          mcb_data_collection.dart
          room_device_state.dart
          device_command.dart
        repositories/
          monitoring_repository.dart
        usecases/
          watch_monitoring_data.dart
          watch_connection_status.dart
          watch_room_devices.dart
          control_room_device.dart
          estimate_energy_cost.dart
          estimate_emission.dart
      data/
        datasources/
          firebase_monitoring_data_source.dart
          firebase_room_device_data_source.dart
        models/
          sensor_data_model.dart
          mcb_data_model.dart
          room_device_state_model.dart
        repositories/
          monitoring_repository_impl.dart
      presentation/
        bloc/
          monitoring_bloc.dart
          monitoring_event.dart
          monitoring_state.dart
        pages/
          monitoring_page.dart
          control_page.dart
        widgets/

    history/
      domain/
        entities/
          historical_mcb_data.dart
        repositories/
          history_repository.dart
        usecases/
          load_history_data.dart
      data/
        datasources/
          firebase_history_data_source.dart
        models/
          historical_mcb_data_model.dart
        repositories/
          history_repository_impl.dart
      presentation/
        bloc/
          history_bloc.dart
          history_event.dart
          history_state.dart
        models/
          chart_point.dart
          history_chart_data.dart
        pages/
          history_page.dart
        widgets/
```

## Step-by-Step Migrasi

### Step 1 - Buat Boundary Folder Baru Tanpa Mengubah Behavior

Buat folder:

```text
lib/app
lib/core
lib/features/monitoring/domain
lib/features/monitoring/data
lib/features/monitoring/presentation
lib/features/history/domain
lib/features/history/data
lib/features/history/presentation
```

Jangan langsung pindahkan semua file. Tujuannya menyiapkan struktur agar migrasi bisa dilakukan kecil-kecil.

Validasi:

```powershell
flutter analyze
flutter test
```

### Step 2 - Pindahkan Repository Contract ke Domain

Pindahkan `MonitoringRepository` dari `lib/services/firebase_service.dart` ke:

```text
lib/features/monitoring/domain/repositories/monitoring_repository.dart
```

Pindahkan `HistoryRepository` ke:

```text
lib/features/history/domain/repositories/history_repository.dart
```

Aturan:

- file repository domain tidak boleh import Firebase;
- file repository domain tidak boleh import Flutter;
- BLoC import repository dari domain, bukan dari `services/firebase_service.dart`.

Validasi:

```powershell
flutter analyze
flutter test test/monitoring_bloc_test.dart
```

### Step 3 - Extract Entity Domain Murni

Mulai dari model yang paling sering dipakai:

```text
SensorData
McbData
McbDataCollection
HistoricalMcbData
DeviceConfig
RoomDeviceConfig
```

Target:

```text
lib/features/monitoring/domain/entities/sensor_data.dart
lib/features/monitoring/domain/entities/mcb_data.dart
lib/features/monitoring/domain/entities/mcb_data_collection.dart
lib/features/history/domain/entities/historical_mcb_data.dart
```

Aturan:

- entity boleh punya constructor, `copyWith`, getter kalkulasi domain, dan value equality;
- entity tidak boleh punya `fromFirestore`, `toFirestore`, atau parsing Firebase;
- fallback data rusak jangan otomatis menjadi `DateTime.now()` di domain.

Validasi:

```powershell
flutter analyze
flutter test
```

### Step 4 - Buat Data Model dan Mapper Firebase

Pindahkan logic parsing Firebase ke data layer:

```text
lib/features/monitoring/data/models/sensor_data_model.dart
lib/features/monitoring/data/models/mcb_data_model.dart
lib/features/history/data/models/historical_mcb_data_model.dart
```

Contoh tanggung jawab:

- `SensorDataModel.fromRealtimeDatabase(Map<String, dynamic> data)`;
- `McbDataModel.fromRealtimeDatabase(Map<String, dynamic> data)`;
- `HistoricalMcbDataModel.fromFirestore(Map<String, dynamic> data, String id)`;
- `HistoricalMcbDataModel.toFirestore()`.

Validasi wajib:

```powershell
flutter test
```

Tambahkan test mapper untuk payload valid, payload null, payload malformed, timestamp Firestore, dan timestamp String.

### Step 5 - Split `FirebaseService`

Pecah service besar menjadi beberapa class:

```text
FirebaseMonitoringDataSource
FirebaseRoomDeviceDataSource
FirebaseHistoryDataSource
MonitoringRepositoryImpl
HistoryRepositoryImpl
```

Tanggung jawab:

- data source hanya bicara dengan Firebase;
- repository implementation mengubah data model ke entity domain;
- repository implementation menangani error data layer menjadi failure atau exception yang konsisten;
- BLoC tetap tidak tahu Firebase path.

Validasi:

```powershell
flutter analyze
flutter test
```

### Step 6 - Tambahkan Use Case

Minimal use case:

```text
WatchMonitoringDataUseCase
WatchConnectionStatusUseCase
WatchRoomDevicesUseCase
ControlRoomDeviceUseCase
LoadHistoryDataUseCase
EstimateEnergyCostUseCase
EstimateEmissionUseCase
```

Setelah ini BLoC memanggil use case, bukan langsung repository untuk semua flow kompleks.

Contoh target dependensi:

```text
MonitoringBloc
  -> WatchMonitoringDataUseCase
  -> WatchConnectionStatusUseCase
  -> WatchRoomDevicesUseCase
  -> ControlRoomDeviceUseCase
```

Validasi:

```powershell
flutter test test/monitoring_bloc_test.dart
```

### Step 7 - Ganti Raw `Map` Menjadi Typed Device State

Ganti state:

```dart
Map<String, dynamic> deviceData
Map<String, dynamic> confirmedDeviceData
```

Menjadi tipe domain/presentation yang jelas, misalnya:

```text
RoomDeviceCollection
RoomDeviceState
DeviceStateValue
PendingDeviceCommand
```

Aturan:

- UI tidak membaca `dbData['rooms']` lagi;
- BLoC tidak menulis node raw `state` dan `brightness` langsung;
- mapping `rooms/<roomKey>/<deviceKey>` hanya ada di data layer;
- `unknown`, `off`, `on`, `pending`, dan `failed` harus berbeda.

Validasi:

```powershell
flutter test test/monitoring_bloc_test.dart
flutter test test/widget_test.dart
```

### Step 8 - Pindahkan Dependency Creation ke Composition Root

Target file:

```text
lib/app/di.dart
lib/main.dart
```

Pindahkan pembuatan dependency konkret dari screen ke root.

Hapus pola ini dari `History`:

```dart
FirebaseService()
```

Target:

```text
main.dart / app/di.dart
  -> membuat Firebase SDK instance
  -> membuat data source
  -> membuat repository implementation
  -> membuat use case
  -> membuat BLoC
```

Validasi:

```powershell
flutter analyze
flutter test
```

### Step 9 - Pindahkan Chart Model dan Business Rule dari UI

Pindahkan:

- `HistoryChartData` dan `ChartPoint` dari `history_bloc.dart` ke presentation model;
- cost estimation dari `monitoring.dart` ke use case;
- emission estimation dari `monitoring.dart` ke use case;
- temperature/humidity classification jika dianggap business rule, pindahkan ke domain atau presentation mapper.

Target:

```text
features/history/presentation/models/history_chart_data.dart
features/history/presentation/models/chart_point.dart
features/monitoring/domain/usecases/estimate_energy_cost.dart
features/monitoring/domain/usecases/estimate_emission.dart
```

Validasi:

```powershell
flutter analyze
flutter test
```

### Step 10 - Tambahkan Architecture Enforcement

Tambahkan test import boundary, misalnya test sederhana yang scan file `.dart`:

Rules minimum:

- file di `domain/` tidak boleh mengandung `package:flutter`, `firebase_`, `cloud_firestore`, `firebase_database`, atau `flutter_bloc`;
- file di `presentation/` tidak boleh import `data/`;
- BLoC tidak boleh import file data source atau Firebase service konkret;
- repository contract hanya ada di domain.

Validasi:

```powershell
flutter test test/architecture_test.dart
```

## Prioritas Eksekusi

Urutan disarankan agar risiko kecil:

1. Pindahkan repository contract ke domain.
2. Pindahkan `HistoryBloc` creation keluar dari `screen/history.dart`.
3. Pisahkan `HistoryChartData` dan `ChartPoint` agar import cycle hilang.
4. Extract entity domain murni dari `models/model.dart`.
5. Buat data model/mapper Firebase.
6. Split `FirebaseService`.
7. Tambahkan use case.
8. Ganti raw device `Map` menjadi typed state.
9. Pindahkan business rule dari UI.
10. Tambahkan architecture test.

## Risiko Jika Tidak Dimigrasikan

- Perubahan schema Firebase akan terus memaksa perubahan di UI dan BLoC.
- Test akan makin sulit karena logic tersebar di widget, BLoC, model, dan service.
- `FirebaseService` akan menjadi semakin besar.
- Bug `unknown` vs `off` bisa muncul karena data hilang default ke `false`.
- Migrasi data source selain Firebase akan mahal.
- Onboarding developer baru lebih sulit karena boundary tidak jelas.

## Kesimpulan

Proyek ini **belum Clean Architecture**, tetapi punya pondasi awal yang cukup baik untuk dimigrasikan bertahap. Perubahan tidak perlu dilakukan sekaligus. Mulai dari memindahkan repository contract ke domain dan mengeluarkan dependency konkret dari screen, lalu lanjut ke entity, mapper, data source, use case, dan typed state.

Target akhir bukan sekadar folder terlihat rapi, tetapi arah dependensi benar:

```text
UI/BLoC -> Use Case -> Repository Contract -> Entity
Data Repository Impl -> Repository Contract
Firebase Data Source -> Firebase SDK
Composition Root -> semua implementasi konkret
```
