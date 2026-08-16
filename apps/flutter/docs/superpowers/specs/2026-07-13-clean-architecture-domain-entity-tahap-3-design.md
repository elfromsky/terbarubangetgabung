# Clean Architecture Domain Entity Tahap 3 Design

## Goal

Memindahkan konsep bisnis monitoring dan history ke entity domain murni. Semua parsing `Map`, alias Realtime Database, serialisasi Firestore, timestamp fallback, dan legacy schema pindah ke data mapper. Firebase path, payload, BLoC state, UI output, dan behavior history tetap sama.

## Scope

Tahap ini mencakup:

- membuat entity domain `SensorData`, `McbData`, `McbDataCollection`, dan `HistoricalMcbData`;
- memindahkan parsing realtime telemetry dan legacy sensor alias ke mapper monitoring;
- memindahkan parsing canonical/legacy Firestore dan legacy serialisasi ke mapper history;
- memperbarui seluruh import production/test dari `lib/models/model.dart` ke entity feature;
- menghapus `lib/models/model.dart` setelah tidak ada import;
- menambah regression test untuk schema canonical, legacy, malformed data, alias sensor, timestamp, dan serialisasi.

Tahap ini tidak mencakup:

- DTO atau model data baru;
- stream/data source/repository contract redesign;
- use case;
- typed device state;
- perubahan Firebase path, Firestore collection, query boundary, command payload, atau UI;
- perubahan fallback timestamp `DateTime.now()`;
- perubahan nullable legacy history field;
- migrasi `DeviceConfig` atau `RoomDeviceConfig`.

## Target Struktur

```text
lib/
  features/
    monitoring/
      domain/
        entities/
          sensor_data.dart
          mcb_data.dart
          mcb_data_collection.dart
        repositories/
          monitoring_repository.dart
      data/
        mappers/
          realtime_monitoring_mapper.dart
        datasources/
          firebase_monitoring_data_source.dart
    history/
      domain/
        entities/
          historical_mcb_data.dart
        repositories/
          history_repository.dart
      data/
        mappers/
          firestore_history_mapper.dart
        datasources/
          firebase_history_data_source.dart
```

Hapus:

```text
lib/models/model.dart
```

`lib/models/device_config.dart` tetap tidak berubah.

## Domain Entities

### `SensorData`

File:

```text
lib/features/monitoring/domain/entities/sensor_data.dart
```

Entity berisi:

```text
constructor
empty()
temperature
humidity
connected
heatIndex
comfortLevel
```

Entity tidak boleh berisi `Map`, `dynamic`, parsing alias, Firebase, Firestore, atau Flutter import.

`heatIndex` dan `comfortLevel` tetap ada karena dipakai `monitoring.dart` dan merupakan perhitungan berdasarkan nilai entity.

### `McbData`

File:

```text
lib/features/monitoring/domain/entities/mcb_data.dart
```

Entity berisi:

```text
constructor
empty()
copyWith()
connected
voltage
current
power
energy
lastUpdate
toString()
```

Entity tidak punya `fromMap()` atau `toMap()`.

### `McbDataCollection`

File:

```text
lib/features/monitoring/domain/entities/mcb_data_collection.dart
```

Entity berisi:

```text
constructor
empty()
copyWith()
mcb1
sensorData
totalCurrent
totalPower
totalEnergy
```

### `HistoricalMcbData`

File:

```text
lib/features/history/domain/entities/historical_mcb_data.dart
```

Entity berisi:

```text
constructor
id
timestamp
nullable mcb1
nullable sensorData
toString()
```

Entity tidak punya factory `fromMcbCollection`, `fromFirestore`, `toMap`, atau `toFirestore`.

## Realtime Mapper

File:

```text
lib/features/monitoring/data/mappers/realtime_monitoring_mapper.dart
```

Public function:

```dart
McbDataCollection mapRealtimeMonitoringData(dynamic value);
SensorData mapRealtimeSensorData(dynamic value);
```

Behavior harus sama:

- root telemetry bukan `Map` menghasilkan `McbDataCollection.empty()`;
- node `environment` dan `power` bukan `Map` menjadi map kosong;
- canonical number menerima `int`, `double`, dan numeric `String`;
- null atau invalid number menjadi `0.0`;
- `connected` true hanya untuk literal `true`;
- canonical telemetry memakai `environment` dan `power`;
- `mapRealtimeSensorData` mendukung `temperature|temp|suhu` serta `humidity|hum|kelembapan`;
- value null atau type salah pada legacy sensor stream menghasilkan `SensorData.empty()`;
- realtime MCB `lastUpdate` tetap `0`.

`firebase_value_parser.dart` tetap memegang `normalizeFirebaseMap()` dan `parseFirebaseDouble()` karena keduanya utility data layer.

`FirebaseMonitoringDataSource` memanggil mapper, tidak membuat entity langsung atau memanggil factory entity parser.

## Firestore Mapper

File:

```text
lib/features/history/data/mappers/firestore_history_mapper.dart
```

Public function:

```dart
DateTime parseFirestoreTimestamp(dynamic timestamp);
HistoricalMcbData mapCanonicalFirestoreHistory(
  Map<String, dynamic> data,
  String id,
);
HistoricalMcbData mapLegacyFirestoreHistory(
  Map<String, dynamic> data,
  String id,
);
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

### Canonical `sensorLogs` behavior

Schema tetap:

```text
timestamp
power
environment
```

Behavior tetap:

- timestamp mendukung Firestore `Timestamp`, ISO String, `dd MMM yyyy at HH:mm:ss`, dan millisecond `int`;
- null, unsupported, atau invalid timestamp menghasilkan `DateTime.now()`;
- `power` atau `environment` yang hilang menghasilkan entity MCB/sensor non-null bernilai nol; node yang ada tetapi bukan `Map` membuat mapper gagal, lalu data source mencetak error dan melompati document seperti behavior lama;
- canonical MCB `lastUpdate` memakai timestamp millisecond;
- canonical parser memakai `parseFirebaseDouble()`.

### Legacy `energyData` behavior

Schema tetap:

```text
timestamp
mcb1
dht
```

Behavior tetap:

- `mcb1` dan `sensorData` null bila node tidak ada;
- timestamp String diparse ISO;
- timestamp object memakai `.toDate()`;
- timestamp hilang menghasilkan `DateTime.now()`;
- parse failure seluruh record menghasilkan `HistoricalMcbData(id: id, timestamp: DateTime.now())`;
- legacy write memakai `id`, native `DateTime timestamp`, `mcb1` map, dan optional `dht` map;
- `mcb1` write menyimpan `connected`, `voltage`, `current`, `power`, `energy`, `lastUpdate`;
- `dht` write hanya menyimpan `temperature` dan `humidity`;
- `toMap` legacy tetap menghasilkan timestamp ISO string.

`FirebaseHistoryDataSource` menggunakan mapper. Query, collection, limit, ordering, error text, `debugPrint`, dan safe empty-list behavior tidak berubah.

## Import Migration

Production/test source mengimpor entity sesuai feature:

```text
monitoring entity imports:
- SensorData
- McbData
- McbDataCollection

history entity imports:
- HistoricalMcbData
- McbData
- SensorData
- McbDataCollection when legacy history write requires it
```

Repository contract hanya import domain entity. BLoC/UI boleh import domain entity. Data mapper/data source/repository boleh import domain entity dan data utility. Tidak ada file di `domain/` import `data/`, `lib/models/model.dart`, Firebase, Flutter, `Map`, atau `dynamic`.

## Migration Order

1. Tambah entity domain dan unit test pure behavior.
2. Tambah realtime mapper plus canonical/alias regression test.
3. Tambah Firestore mapper plus canonical/legacy/serialization regression test.
4. Ubah data source memakai mapper.
5. Migrasikan import repository, BLoC, state/event, UI, tests.
6. Hapus `lib/models/model.dart` hanya setelah project search tidak menemukan import/path/file reference.
7. Tambah architecture test domain entity purity dan deleted legacy model.

## Error Handling

Tidak ada perubahan visible error behavior.

- Realtime malformed root tetap menjadi empty collection.
- Realtime legacy sensor malformed data tetap menjadi empty sensor.
- Canonical Firestore parsing failure per document tetap dicetak lalu dilewati source.
- Canonical history query failure tetap `Exception('Failed to fetch historical data: $error')`.
- Legacy safe history query/parsing failure tetap `[]`.
- Legacy record mapping failure tetap timestamp sekarang dan nullable metric fields.
- Command behavior tidak disentuh.

## Tests

Tambah/ubah test berikut:

- entity test untuk empty, copyWith, aggregate, heatIndex, comfortLevel;
- realtime mapper test untuk malformed root, null number, numeric string, nested map, sensor alias, malformed sensor value;
- Firestore mapper test untuk Timestamp, ISO, display timestamp, millisecond, invalid timestamp fallback, canonical schema, legacy `mcb1/dht`, missing node, malformed legacy record, `toFirestore`, dan `toMap`;
- data source test mempertahankan public parser behavior dengan import mapper/function baru;
- architecture test memastikan `lib/models/model.dart` hilang;
- architecture test memastikan domain entity source tidak mengandung forbidden package/data imports atau `Map<`/`dynamic`;
- existing monitoring/history/BLoC/widget/repository test tetap lulus setelah import migration.

## Acceptance Criteria

- `lib/models/model.dart` tidak ada.
- Semua 15 direct import sebelumnya pindah ke entity feature.
- Domain repository contract import entity domain, bukan `lib/models/model.dart`.
- Domain entity tidak punya `fromMap`, `toMap`, `fromFirestore`, `toFirestore`, `Map`, `dynamic`, Firebase, Firestore, Flutter, atau data import.
- Realtime telemetry, sensor aliases, canonical history, legacy history, legacy save serialization, timestamp fallback, nullable legacy field, dan `lastUpdate` behavior memiliki regression test.
- Firebase data source tidak membuat entity langsung dari raw map; source memakai mapper.
- Firebase path, query, payload, BLoC state shape, and UI output tidak berubah.
- `dart format --output=none --set-exit-if-changed` pada scope perubahan, `flutter analyze`, `flutter test`, dan `flutter build apk --debug` lulus.

## Next Migration

Tahap 4 dapat menambah use case untuk stream monitoring, command device, history load, biaya energi, dan emisi. Tahap itu membuat BLoC bergantung ke use case, bukan repository contract langsung.
