# Typed Device State Plan 7 UI/UX Design

## Status

Design approved by user.

## Goal

Mengubah status perangkat dari raw Firebase map menjadi typed state, lalu menampilkan status `unknown`, `off`, `on`, `pending`, dan `failed` secara jelas tanpa redesign visual besar.

## Product Context

- Product: Flutter Android app monitoring telemetry dan kontrol perangkat rumah.
- Primary user: operator/pengguna rumah yang melihat status perangkat dan mengirim command ON/OFF/brightness.
- Primary screens: `MonitoringPage`, `ControlPage`.
- Existing routes tetap `/`, `/control`, `/history`.
- Existing theme tetap dark olive-to-yellow gradient, translucent cards, Material icons, current typography, spacing, radius, dan layout.
- Existing target minimum Android tetap berlaku.
- Existing responsive test memakai lebar `320` dan text scale `2x`.
- Tidak ada `design-system/MASTER.md` atau page override.

## Facts, Decisions, Assumptions

### Facts

- Firebase room state memiliki state-only bool dan dimmable object `{state, brightness}`.
- Firebase `/rooms` menjadi source of truth confirmed hardware state.
- Firebase command write hanya berarti command queued.
- Current BLoC menyimpan raw maps pada `deviceData` dan `confirmedDeviceData`.
- Current UI membaca `rooms`, `state`, dan `brightness` langsung.
- Current UI default malformed/missing device menjadi OFF.
- Current pending/error behavior sudah ada pada command flow.

### Decisions

- Preserve route, theme, visual hierarchy, command labels, Firebase path, payload, timeout, rollback, and confirmation semantics.
- Unknown tidak boleh ditampilkan sebagai OFF.
- Pending men-disable control perangkat terkait.
- Failed menampilkan error dan mengaktifkan control kembali bila confirmed value tersedia.
- Status tidak boleh memakai warna sebagai satu-satunya sinyal.
- Tidak menambah dependency.
- Tidak mengubah cost/emission UI atau history UI.

### Assumptions

- Tidak ada caller luar package untuk room data source API.
- Android menjadi target utama; keyboard/accessibility checks tetap diterapkan pada semantic Flutter controls.
- Existing theme tidak diganti.

## Non-Goals

- Redesign visual besar.
- Perubahan navigation atau route.
- Perubahan Firebase schema, command payload, query, firmware contract, atau hardware behavior.
- Penggabungan status hardware `kamar_1/lampu` dan `kamar_2/lampu`; shared dimmer tetap contract firmware.
- Perubahan cost/emission calculation.
- Perubahan history chart.
- Penambahan animation library atau state-management library.

## Success Criteria

- Raw `Map<String, dynamic>` tidak keluar dari data layer untuk room state.
- `MonitoringBloc`, `MonitoringState`, dan UI memakai typed room-device state.
- Unknown tidak tampil sebagai `Mati` atau `OFF`.
- Pending, failed, confirmed, on, dan off berbeda secara teks, icon, semantic state, atau control availability.
- Command A pending tidak memblokir command B.
- Confirmed update perangkat lain tidak menghapus pending perangkat A.
- Write failure dan timeout rollback ke confirmed snapshot.
- Firebase path dan payload tetap identik.
- Existing UI layout/theme tetap.
- `flutter analyze`, full tests, architecture tests, dan debug APK lulus.

## Information Architecture and User Flow

### Monitoring screen

Existing hierarchy tetap:

```text
Appbar
  PageSelector
    Monitoring category selector
  Connection status
  Telemetry cards / sensor cards / electronic status cards
```

Electronic status card menampilkan tiap room dan device. Device status memiliki:

```text
Device name
Capability icon
Status label
Optional brightness
Optional semantic error/pending indicator
```

### Control screen

Existing hierarchy tetap:

```text
Appbar
  PageSelector
    Room selector
  Firebase connection warning
  Hardware status card
  Control panel card
```

Control action tetap:

- state-only: `Nyalakan`, `Matikan`;
- dimmable: `Nyala`, `Mati`, slider, `Send`;
- retry monitoring tetap `Coba lagi`.

### Device flow

```text
loading
  status belum tersedia

confirmed off
  status Mati

confirmed on
  status Nyala

user sends command
  status Menunggu konfirmasi
  control terkait disabled

rooms update matches desired
  status Nyala/Mati
  control enabled

write failure or timeout
  rollback confirmed value
  status error
  control enabled when confirmed value exists
```

No route or navigation change.

## Visual Direction

### Existing theme preservation

Use existing values and components. No new global theme.

- Background: existing dark olive-to-yellow gradient.
- Card: existing translucent white surface and border.
- Text: existing white/white70 hierarchy.
- Existing green/red/amber/grey status colors remain supporting signals.
- Existing Material icon family remains.
- Existing radius, padding, and button shapes remain.

### Status treatment

Status must combine text, icon, and control state:

| Phase | Label | Icon | Control |
| --- | --- | --- | --- |
| `unknown` | `Status belum tersedia` | `help_outline` | Disabled |
| `off` | `Mati` / `OFF` using existing screen copy | `power_off` | Enabled |
| `on` | `Nyala` / `ON` using existing screen copy | `power` | Enabled |
| `pending` | `Menunggu konfirmasi` | `sync` or existing progress indicator | Disabled |
| `failed` | Existing error message | `error_outline` | Enabled when value known |

`pending` uses compact `CircularProgressIndicator` already used by `_ControlActionWidget`; no new motion system.

`failed` keeps existing error text, adds semantic error role, and does not erase confirmed value.

### Contrast

- Normal text target: minimum `4.5:1`.
- Status meaning cannot rely on green/red/grey alone.
- Existing color choices remain only after contrast verification on current gradient/card surfaces.
- No emoji as structural status icon.

## Domain and Presentation Model

### Domain entities

Create typed room state under monitoring domain:

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
```

```dart
class RoomDeviceValue {
  final bool isOn;
  final int? brightness;

  const RoomDeviceValue({
    required this.isOn,
    this.brightness,
  });

  bool get isDimmable => brightness != null;
}
```

Rules:

- state-only bool `true` becomes `RoomDeviceValue(isOn: true)`;
- state-only bool `false` becomes `RoomDeviceValue(isOn: false)`;
- dimmable object keeps `brightness` as non-null, including `0` when off;
- brightness is normalized to `0..100` by data mapper;
- missing device remains absent, meaning unknown;
- unknown never becomes `RoomDeviceValue(isOn: false)`.

```dart
class RoomDeviceCollection {
  final Map<DeviceAddress, RoomDeviceValue> values;

  const RoomDeviceCollection({required this.values});

  factory RoomDeviceCollection.empty();

  RoomDeviceValue? find(DeviceAddress address);
  RoomDeviceCollection set(DeviceAddress address, RoomDeviceValue value);
}
```

`RoomDeviceCollection` is immutable from consumer perspective. `set` returns new collection and does not mutate previous snapshot.

### BLoC state

```dart
class MonitoringLoaded extends MonitoringState {
  final McbDataCollection mcbData;
  final bool isConnected;
  final RoomDeviceCollection deviceData;
  final RoomDeviceCollection confirmedDeviceData;
  final Set<DeviceAddress> pendingDevices;
  final Map<DeviceAddress, String> commandErrors;
}
```

`pendingDevices` and `commandErrors` use `DeviceAddress`, not combined strings such as `teras/lampu`.

### Presentation view state

Create:

```text
lib/features/monitoring/presentation/models/device_control_view_state.dart
```

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
}
```

Create presentation mapper:

```text
lib/features/monitoring/presentation/mappers/device_control_view_mapper.dart
```

```dart
DeviceControlViewState mapDeviceControlViewState({
  required RoomDeviceCollection visibleDevices,
  required DeviceAddress address,
  required bool isPending,
  required String? errorMessage,
});
```

Priority:

```text
errorMessage != null  = failed
isPending             = pending
value == null         = unknown
value.isOn == true    = on
value.isOn == false   = off
```

Failed command normally retains confirmed/visible value after rollback. If no value exists, UI keeps controls disabled despite failed label to avoid sending from unknown state.

## Data Flow

```text
Firebase rooms raw map
  FirebaseRoomDeviceDataSource
  RoomDeviceCollectionDto
  RoomDeviceMapper
  RoomDeviceCollection entity
  MonitoringRepositoryImpl
  WatchRoomDevicesUseCase
  MonitoringBloc
  MonitoringLoaded typed state
  DeviceControlViewMapper
  MonitoringPage / ControlPage
```

Only data mapper knows `rooms`, `state`, and `brightness` keys.

### Mapping rules

- root null/non-map: empty collection;
- room non-map: ignore room;
- state-only bool: typed value with null brightness;
- dimmable map: `state` literal bool, `brightness` numeric normalized to integer `0..100`;
- malformed device node: ignore node, do not invent OFF;
- unknown room/device: absent lookup;
- Firebase command write path and payload unchanged.

## BLoC State Transitions

### Initial confirmed snapshot

```text
confirmed = collection from /rooms
visible = confirmed
pending = empty
errors = empty
```

### Optimistic command

```text
visible = visible.set(address, desired)
confirmed = unchanged
pending += address
errors[address] removed
```

### Command write success

```text
pending remains until /rooms matches
```

### Matching `/rooms` update

```text
confirmed = update
if desired == confirmed[address]:
  pending remove address
  error remove address
else:
  visible keeps desired for address while pending
```

### Write failure

```text
pending remove address
visible restore from confirmed
errors[address] = existing write error text
```

### Timeout

```text
pending remove address
visible restore from confirmed
errors[address] = existing timeout error text
```

### Unrelated device update

Confirmed snapshot updates all devices. Pending device desired state remains visible only for its own address. Other devices immediately show confirmed values.

## Responsive Rules

- Preserve current scroll-based layout.
- Preserve current card width and spacing.
- No horizontal overflow at `320px` with text scale `2x`.
- Status labels may wrap or ellipsize without hiding device name.
- Pending/error indicators stay compact and do not shift card layout materially.
- Buttons retain Android minimum touch target `48x48dp` where practical; existing `ElevatedButton` minimums remain.
- Brightness slider remains disabled during pending and unknown.
- No new fixed-position overlay.

## Motion

- Reuse existing progress indicator for pending.
- No new animation dependency.
- No layout-shifting status animation.
- Status transition can update on normal Flutter rebuild.
- Respect reduced-motion platform behavior by avoiding custom animation.

## Accessibility

- Every status exposes text label and semantic state.
- Color is never sole status signal.
- Buttons retain accessible text labels: `Nyalakan`, `Matikan`, `Send`, `Coba lagi`.
- Unknown/pending controls have disabled semantics and explanatory status text.
- Failed state exposes error text, not only red color/icon.
- Focus order follows room, device, status, then control actions.
- Interactive controls retain at least `48x48dp` Android target where applicable.
- Existing text scale `2x` test remains required.
- No emoji structural icons.

## Performance

- Typed collection updates copy only affected immutable map snapshot at current app scale.
- No new streams, polling, animation loop, or network call.
- Device mapper runs once per Firebase snapshot.
- UI uses existing room config list; no unbounded list change.

## Error Recovery

- Firebase stream error keeps existing monitoring error handling.
- Device command write failure keeps existing per-device error.
- Timeout keeps existing per-device timeout message.
- Retry monitoring CTA remains unchanged.
- Failed command does not mark telemetry failed.
- Rollback returns latest confirmed snapshot, not stale initial snapshot.

## Testing and Acceptance

### Domain tests

- `DeviceAddress` equality/hashCode.
- state-only on/off values.
- dimmable on/off values and brightness `0..100`.
- collection lookup/set immutability.
- missing lookup remains unknown.

### Mapper tests

- null/non-map root.
- valid bool node.
- valid dimmable node.
- numeric brightness int/double/string.
- brightness clamping.
- malformed room/device nodes ignored.
- no malformed node converted to OFF.

### BLoC tests

- typed room stream creates loaded state.
- start remains idempotent.
- matching update clears pending.
- stale mismatch keeps pending.
- write failure rollback.
- timeout rollback.
- unrelated device update while one pending.
- duplicate command for pending address rejected.
- device-specific errors.
- close cancels timers/subscriptions.

### Widget tests

- unknown status not rendered as OFF.
- pending disables related controls.
- failed renders error and re-enables known control.
- state-only hides brightness.
- dimmable displays brightness.
- existing `320px`/text-scale test passes.

### Architecture tests

- repository contract exposes typed room collection, not raw map;
- use case exposes typed room collection;
- BLoC and screens contain no Firebase room key parsing;
- Firebase room key parsing exists only in data mapper;
- presentation does not import data layer;
- domain has no Firebase/Flutter/data imports.

## Rollout and Rollback

Rollout is one feature slice after all targeted tests pass. No Firebase migration or firmware change required.

Rollback is file-level Git revert of Plan 7 changes. Firebase schema and command payload remain backward-compatible, so rollback restores old raw-map consumer without backend migration.

## Plan 7 Acceptance Criteria

- `RoomDeviceCollection`, `DeviceAddress`, and `RoomDeviceValue` replace raw room maps in repository/use case/BLoC state/UI.
- `unknown`, `off`, `on`, `pending`, and `failed` have distinct semantic behavior.
- UI preserves existing theme, route, layout, labels, and visual direction.
- Firebase mapper remains only location that knows `rooms`, `state`, and `brightness`.
- Optimistic, confirmed, timeout, write-failure, and rollback behavior remains correct.
- No Firebase path, payload, DTO telemetry, history flow, or Plan 9 cost/emission logic changes.
- `flutter analyze`, `flutter test`, architecture tests, and `flutter build apk --debug` pass.
