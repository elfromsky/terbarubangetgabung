# Clean Architecture Data Layer Tahap 2 Design

## Goal

Memecah `FirebaseService` menjadi data source Firebase dan repository implementation per feature tanpa mengubah Firebase path, payload command, hasil stream, query history, atau behavior BLoC/UI.

## Scope

Tahap ini mencakup:

- mengganti `FirebaseService` dengan tiga Firebase data source;
- membuat `MonitoringRepositoryImpl` dan `HistoryRepositoryImpl`;
- memindahkan Firebase SDK singleton dari service lama ke constructor data source;
- memperbarui `AppDependencies` agar menyusun data source dan repository implementation;
- mempertahankan seluruh method legacy yang tidak dipakai source app saat ini;
- menambah test untuk boundary, mapper behavior, path command, dan wiring dependency.

Tahap ini tidak mencakup:

- memindahkan entity dari `lib/models/model.dart`;
- membuat model data terpisah atau mapper entity murni;
- use case;
- typed device state;
- perubahan Firebase schema, Firebase rules, command, atau UI;
- penghapusan API legacy `energyData`;
- perubahan error contract yang terlihat BLoC/UI.

## Target Struktur

```text
lib/
  app/
    app_dependencies.dart
  features/
    monitoring/
      data/
        datasources/
          firebase_monitoring_data_source.dart
          firebase_room_device_data_source.dart
        repositories/
          monitoring_repository_impl.dart
      domain/
        repositories/
          monitoring_repository.dart
    history/
      data/
        datasources/
          firebase_history_data_source.dart
        repositories/
          history_repository_impl.dart
      domain/
        repositories/
          history_repository.dart
```

`lib/services/firebase_service.dart` dihapus. Tidak ada layer di luar `data` yang import Firebase Realtime Database atau Cloud Firestore.

## Dependency Direction

```text
AppDependencies
  imports Firebase SDK, data source, repository implementation, repository contract

MonitoringRepositoryImpl
  imports MonitoringRepository domain contract
  imports FirebaseMonitoringDataSource dan FirebaseRoomDeviceDataSource

HistoryRepositoryImpl
  imports HistoryRepository domain contract
  imports FirebaseHistoryDataSource

Firebase data source
  imports Firebase SDK dan lib/models/model.dart

BLoC
  imports repository contract domain
```

Repository implementation pada tahap ini tetap meneruskan object model dari data source karena entity/data-model split adalah tahap berikutnya. Pemisahan tanggung jawab tetap jelas: data source memahami SDK dan path; repository memenuhi contract aplikasi.

## Firebase Monitoring Data Source

Path dan behavior yang harus sama:

```text
Telemetry: device/sensorData
Connection: .info/connected
```

Class:

```dart
class FirebaseMonitoringDataSource {
  final DatabaseReference database;

  FirebaseMonitoringDataSource({required this.database});

  Stream<McbDataCollection> getMonitoringDataStream();
  Stream<SensorData> getSensorDataStream();
  Stream<Map<String, dynamic>> getRawDatabaseStream();
}
```

`getMonitoringDataStream()` mempertahankan:

- payload bukan `Map` menghasilkan `McbDataCollection.empty()`;
- `environment` dan `power` yang tidak valid menjadi map kosong;
- numerik `int`, `double`, dan `String` diparse seperti behavior lama;
- key telemetry tetap `temperature`, `humidity`, `connected`, `voltage`, `current`, `power`, dan `energy`.

`getSensorDataStream()` dan `getRawDatabaseStream()` dipertahankan walau belum dipakai app source.

## Firebase Room Device Data Source

Path dan behavior yang harus sama:

```text
Read confirmed state: rooms
Write command: commands/rooms/<roomKey>/<deviceKey>
```

Class:

```dart
class FirebaseRoomDeviceDataSource {
  final DatabaseReference database;

  FirebaseRoomDeviceDataSource({required this.database});

  Stream<Map<String, dynamic>> getRoomDevicesStream();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}
```

Aturan write tidak berubah:

- device `supportsBrightness == true` menulis object `{state, brightness}`;
- device state-only menulis `bool` langsung;
- path tetap dibentuk `commands/rooms/$roomKey/$deviceKey`;
- kegagalan write tetap melempar `Exception('Failed to control device: $e')`.

## Firebase History Data Source

Collection canonical tetap:

```text
sensorLogs
```

Class:

```dart
class FirebaseHistoryDataSource {
  final FirebaseFirestore firestore;

  FirebaseHistoryDataSource({required this.firestore});

  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });

  Future<List<HistoricalMcbData>> getTodayHistoryData();
  Future<List<HistoricalMcbData>> getWeekHistoryData();
  Future<List<HistoricalMcbData>> getMonthHistoryData();
  Future<List<HistoricalMcbData>> getAllHistoryData();
  Future<List<HistoricalMcbData>> getHistoricalDataSafe({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 100,
  });
  Future<List<HistoricalMcbData>> getAllHistoryDataSafe();
  Future<void> debugFirestoreData();
  Future<void> saveHistoricalData(McbDataCollection collection);
}
```

Behavior canonical history tidak berubah:

```text
collection('sensorLogs')
.where('timestamp', isGreaterThanOrEqualTo: startDate)
.where('timestamp', isLessThan: endDate)
.orderBy('timestamp', descending: false)
.limit(limit)
```

Legacy method tetap memakai collection `energyData`, exact boundary saat ini, dan `HistoricalMcbData.fromFirestore` atau `toFirestore` seperti behavior lama. Tidak ada feature legacy baru.

Data source memegang private parser berikut:

```text
_convertToMapStringDynamic
_parseDouble
_parseFirestoreTimestamp
_parseHistoricalData
```

`debugPrint` dipindahkan dari service lama ke history data source agar parsing error behavior tidak berubah.

## Repository Implementations

`MonitoringRepositoryImpl`:

```dart
class MonitoringRepositoryImpl implements MonitoringRepository {
  final FirebaseMonitoringDataSource monitoringDataSource;
  final FirebaseRoomDeviceDataSource roomDeviceDataSource;
}
```

Delegasi:

```text
getMonitoringDataStream  -> monitoringDataSource
getRoomDevicesStream     -> roomDeviceDataSource
getConnectionStatus      -> monitoringDataSource
controlRoomDevice        -> roomDeviceDataSource
```

`HistoryRepositoryImpl`:

```dart
class HistoryRepositoryImpl implements HistoryRepository {
  final FirebaseHistoryDataSource historyDataSource;
}
```

`getHistoricalData()` hanya delegasi ke `historyDataSource` dengan parameter yang sama.

Tidak ada Firebase SDK import dalam repository implementation.

## AppDependencies

`AppDependencies.firebase()` membuat satu reference Realtime Database dan satu instance Firestore:

```dart
final database = FirebaseDatabase.instance.ref();
final firestore = FirebaseFirestore.instance;

final monitoringDataSource = FirebaseMonitoringDataSource(database: database);
final roomDeviceDataSource = FirebaseRoomDeviceDataSource(database: database);
final historyDataSource = FirebaseHistoryDataSource(firestore: firestore);
```

Lalu membuat repository implementation dan memasukkannya ke dua field contract. `EshApp`, BLoC, routing, dan widget tidak berubah.

Firebase instance hanya dibuat setelah `FirebaseBootstrap` berhasil, seperti tahap 1.

## Testing

Tambah unit test tanpa Firebase emulator:

- helper parser monitoring menerima `int`, `double`, `String`, null, nested map, dan malformed root;
- helper room data source mempertahankan wrapper `{'rooms': ...}` saat nilai rooms valid atau invalid;
- repository implementation meneruskan stream, command parameter, dan history parameter ke fake data source;
- architecture test memastikan `lib/services/firebase_service.dart` tidak ada;
- architecture test memastikan BLoC, screen, domain, dan repository implementation tidak import Firebase SDK;
- architecture test memastikan Firebase package hanya di `lib/app` dan `features/*/data/datasources`;
- test dependency memastikan factory constructor injection tetap memungkinkan fake repository.

Firebase SDK types sulit difake tanpa wrapper tambahan. Data source parser dipecah sebagai function public/package-local murni jika perlu agar unit test tidak memerlukan `DatabaseEvent`, `Query`, atau Firestore query fake. Tidak tambah package mocking pada tahap ini.

## Error Handling

Tidak ada perubahan error yang terlihat pemanggil:

- stream telemetry mengembalikan empty object untuk malformed root seperti sebelumnya;
- history canonical membungkus kegagalan query dengan `Exception('Failed to fetch historical data: $e')`;
- command write membungkus kegagalan dengan `Exception('Failed to control device: $e')`;
- history parsing document gagal dicetak dengan `debugPrint` lalu record dilewati;
- legacy safe methods tetap mengembalikan `[]` ketika query atau parsing gagal.

## Acceptance Criteria

- `lib/services/firebase_service.dart` tidak ada.
- `AppDependencies` tidak import `FirebaseService`.
- Semua Firebase path dan collection sama dengan sebelum tahap 2.
- `MonitoringRepositoryImpl` dan `HistoryRepositoryImpl` implement domain contract dan tidak import Firebase SDK.
- Firebase SDK import hanya terdapat di `lib/app`, `lib/firebase_options.dart`, dan feature data source.
- Method legacy dipertahankan pada Firebase data source sesuai behavior lama.
- `MonitoringBloc`, `HistoryBloc`, screen, route, event, dan state tidak diubah untuk behavior data.
- `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, dan `flutter build apk --debug` lulus.

## Next Migration

Tahap 3 memindahkan `SensorData`, `McbData`, `McbDataCollection`, dan `HistoricalMcbData` ke entity domain murni. Mapper Firebase kemudian dipisah dari entity/model lama agar domain tidak mengetahui Map atau Firestore serialization.
