# Clean Architecture Data Model DTO Step 4 Design

## Goal

Melengkapi Step 4 dengan data model/DTO internal untuk semua schema Firebase. Data source mengubah raw Firebase menjadi DTO. Repository implementation mengubah DTO menjadi entity domain. BLoC, UI, dan repository contract tetap hanya menerima entity.

## Scope

Step ini mencakup:

- DTO Realtime telemetry dan sensor alias;
- DTO canonical Firestore `sensorLogs`;
- DTO legacy Firestore `energyData`;
- mapper raw Firebase ke DTO;
- mapper DTO ke entity domain;
- mapper legacy entity ke DTO serialisasi;
- data source interface return DTO;
- repository implementation map DTO stream/future ke entity;
- regression test parsing, conversion, serialisasi, delegasi, dan architecture boundary.

Step ini tidak mencakup:

- Firebase path/query/collection/payload change;
- BLoC, UI, route, state, event, atau repository contract change;
- use case;
- typed room device state;
- `DeviceConfig` migration;
- changes to command payload/confirmation/timeout behavior;
- external compatibility adapter, karena pemilik menyatakan tidak ada caller luar package untuk data source API.

## Target Structure

```text
lib/features/
  monitoring/
    data/
      models/
        realtime_monitoring_dto.dart
        sensor_data_dto.dart
      mappers/
        realtime_monitoring_mapper.dart
        monitoring_entity_mapper.dart
      datasources/
        firebase_monitoring_data_source.dart
      repositories/
        monitoring_repository_impl.dart
  history/
    data/
      models/
        canonical_history_dto.dart
        legacy_history_dto.dart
      mappers/
        firestore_history_mapper.dart
        history_entity_mapper.dart
      datasources/
        firebase_history_data_source.dart
      repositories/
        history_repository_impl.dart
```

Entity tetap:

```text
features/monitoring/domain/entities/
features/history/domain/entities/
```

## DTO Rules

- DTO boleh punya `Map`, `dynamic`, Firebase `Timestamp`, schema key, dan serialization.
- DTO tidak import Flutter, BLoC, UI, repository contract, atau domain entity.
- DTO tidak punya business rule `heatIndex`, `comfortLevel`, aggregate, atau UI format.
- DTO tidak mengembalikan entity lewat `toEntity()`.
- Mapper khusus mengonversi DTO ke entity dan entity ke DTO. Ini menjaga arah tanggung jawab jelas.

## Realtime DTO

### `RealtimeMonitoringDto`

Fields:

```text
environment map
power map
```

Factory:

```dart
factory RealtimeMonitoringDto.fromRealtimeDatabase(dynamic value);
```

Behavior tetap:

- root bukan `Map` menghasilkan DTO kosong;
- nested `environment`/`power` bukan `Map` menjadi map kosong;
- recursive key normalization tetap;
- raw number belum berubah ke `double` di DTO.

### `SensorDataDto`

Fields:

```text
temperature raw value
humidity raw value
connected raw bool
```

Factory:

```dart
factory SensorDataDto.fromRealtimeDatabase(dynamic value);
```

Behavior tetap:

- root bukan `Map` menghasilkan DTO kosong;
- baca alias `temperature|temp|suhu` dan `humidity|hum|kelembapan`;
- `connected` true hanya literal `true`.

### Monitoring Entity Mapper

```dart
McbDataCollection mapRealtimeMonitoringDtoToEntity(
  RealtimeMonitoringDto dto,
);
SensorData mapSensorDataDtoToEntity(SensorDataDto dto);
```

Mapper memakai `parseFirebaseDouble()` untuk `int`, `double`, numeric String, null/invalid. Entity hasil mempertahankan canonical telemetry/default behavior dan `lastUpdate == 0`.

## Firestore DTO

### `CanonicalHistoryDto`

Schema:

```text
timestamp
power
environment
id
```

Factory:

```dart
factory CanonicalHistoryDto.fromFirestore(
  Map<String, dynamic> data,
  String id,
);
```

Behavior:

- `power`/`environment` hilang menjadi empty map;
- present non-`Map` tetap throw TypeError ketika cast, sehingga `FirebaseHistoryDataSource` mencetak error dan skip document seperti behavior lama;
- timestamp raw tetap DTO value.

### `LegacyHistoryDto`

Schema:

```text
id
timestamp
mcb1
dht
```

Factory:

```dart
factory LegacyHistoryDto.fromFirestore(
  Map<String, dynamic> data,
  String id,
);
```

Behavior:

- field raw tetap nullable;
- field invalid dapat dilempar ke `HistoryEntityMapper`, yang mengembalikan historical entity fallback timestamp sekarang dan metric nullable seperti behavior lama.

Serialization tetap di mapper entity-ke-DTO:

```dart
LegacyHistoryDto mapLegacyHistoricalEntityToDto(
  HistoricalMcbData entity,
  {required bool timestampAsIsoString},
);
```

`LegacyHistoryDto.toMap()` menghasilkan native `DateTime` untuk Firestore atau ISO string untuk map sesuai field timestamp DTO. `mcb1` tetap lengkap; `dht` hanya temperature/humidity.

### History Entity Mapper

```dart
DateTime parseFirestoreTimestamp(dynamic timestamp);
HistoricalMcbData mapCanonicalHistoryDtoToEntity(CanonicalHistoryDto dto);
HistoricalMcbData mapLegacyHistoryDtoToEntity(LegacyHistoryDto dto);
```

Behavior tetap:

- canonical timestamp mendukung Timestamp, ISO, `dd MMM yyyy at HH:mm:ss`, millisecond int, invalid/null fallback `DateTime.now()`;
- canonical MCB/sensor selalu non-null; MCB `lastUpdate` timestamp milliseconds;
- legacy timestamp String parse ISO, nonnull object calls `.toDate()`, absent fallback now;
- legacy missing mcb1/dht menghasilkan null fields;
- legacy parsing exception menghasilkan entity id sama, timestamp sekarang, null metrics.

## Data Source Interfaces

```dart
abstract interface class MonitoringDataSource {
  Stream<RealtimeMonitoringDto> getMonitoringDataStream();
  Stream<bool> getConnectionStatus();
}

abstract interface class HistoryDataSource {
  Future<List<CanonicalHistoryDto>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}
```

Legacy public data-source methods return DTO list. No external caller exists.

`FirebaseMonitoringDataSource` reads path sama dan mengembalikan `RealtimeMonitoringDto`. `getSensorDataStream()` mengembalikan `SensorDataDto`.

`FirebaseHistoryDataSource`:

- canonical query mengembalikan canonical DTO;
- canonical DTO factory error tetap `debugPrint` lalu skip;
- legacy methods mengembalikan legacy DTO;
- `saveHistoricalData()` menerima `LegacyHistoryDto`; repository atau mapper membuat DTO dari entity bila caller baru ditambahkan. Tidak ada caller saat ini, jadi signature internal boleh berubah.

## Repository Implementations

`MonitoringRepositoryImpl` maps telemetry DTO stream:

```dart
return monitoringDataSource
  .getMonitoringDataStream()
  .map(mapRealtimeMonitoringDtoToEntity);
```

Room/command/connection behavior unchanged.

`HistoryRepositoryImpl` maps canonical DTO list:

```dart
final dto = await historyDataSource.getHistoricalData(...);
return dto.map(mapCanonicalHistoryDtoToEntity).toList();
```

Repository imports data models/mappers plus domain contract/entity. Firebase SDK stays absent.

## Behavior Invariants

- Realtime telemetry: `device/sensorData` same path and numeric handling.
- Sensor stream alias handling unchanged.
- Canonical history: `sensorLogs`, `>= start`, `< end`, ascending, limit unchanged.
- Canonical malformed present node: source logs then skips doc.
- Legacy history: `energyData`, inclusive safe end-date, empty safe result, legacy field nullability unchanged.
- Legacy save uses same id/timestamp/schema.
- All exception messages, `debugPrint`, BLoC state, and UI output unchanged.

## Tests

- DTO factory test realtime malformed/nested map/aliases;
- DTO factory test canonical missing versus invalid map; legacy raw fields;
- entity mapper test realtime numeric/null/invalid; canonical timestamp/lastUpdate; legacy nullable/fallback;
- DTO serialization test native Firestore timestamp vs ISO map timestamp;
- repository test map DTO stream/future into exact entity fields;
- architecture test confirms data sources return DTO, repository contracts stay entity, DTO avoids Flutter/BLoC/domain implementation import;
- existing integration/BLoC/widget tests keep passing.

## Acceptance Criteria

- `data/models/` has Realtime, sensor, canonical history, legacy history DTO.
- Firebase data source public interfaces use DTO, no entity.
- Repository interfaces return entity, no DTO.
- Repository implementations perform DTO-to-entity mapping.
- DTO has schema/serialization only; entity has no Map/Firebase/serialization.
- Firebase paths, collections, query semantics, payload, error behavior, and UI behavior unchanged.
- Canonical/legacy DTO conversions have regression tests.
- `flutter analyze`, `flutter test`, `flutter build apk --debug`, formatter scope, architecture tests pass.

## Next Step

Step 5 technically complete after this DTO migration. Next unfinished original step: Step 6 use case layer.
