# Integrasi Flutter, Master, dan Slave

## Alur Data

```text
Flutter
  -> /commands/rooms/<roomKey>/tools/<deviceKey>
  -> mastergabung
  -> relay master atau ESP-NOW slavegabung
  -> actual state kembali ke mastergabung
  -> /rooms/<roomKey>/tools/<deviceKey>
  -> Flutter
```

Flutter tidak terhubung langsung ke ESP-NOW.

## Firebase Contract

### Relay

```json
{"state": true}
```

### Dimmer

```json
{"state": true, "brightness": 75}
```

Aturan:

- hanya canonical path dengan node `tools`;
- relay hanya memiliki `state` boolean;
- dimmer memiliki `state` boolean dan brightness integer `0..100`;
- ON dengan brightness `0` menjadi `1`;
- OFF mempertahankan brightness terakhir;
- tidak ada `protocolVersion`, Firebase `requestId`, `createdAt`, atau `source`;
- `/commands` tidak dihapus master;
- `/rooms` hanya ditulis master dari actual state.

## UI Confirmation

Flutter menulis desired state ke `/commands`, lalu menampilkan pending. ON/OFF dan brightness aktual tidak berubah sampai listener `/rooms` menerima state baru.

Timeout pending tidak mengubah actual UI. Jika actual state datang terlambat setelah gangguan Wi-Fi, UI tetap mengikuti `/rooms`.

## Shared Dimmer

`kamar_1/lampu` dan `kamar_2/lampu` berbagi channel dimmer 1.

- Relay ON/OFF independen.
- Brightness selalu sama.
- Flutter memakai multi-location update ketika brightness shared berubah dan state pasangan sudah diketahui.
- Slave mengirim full snapshot setelah command dimmable agar actual kedua lampu segera sinkron.
- Channel dimmer mati hanya saat kedua relay OFF.

## Device Contract

| Room | Device | Owner | Capability | Hardware |
| --- | --- | --- | --- | --- |
| `teras` | `lampu` | Master | relay | GPIO 13 |
| `teras` | `sanyo` | Master | relay | GPIO 14 |
| `lorong` | `stop_kontak` | Slave | relay | GPIO 4 |
| `lorong` | `blower` | Slave | relay | GPIO 5 |
| `kamar_1` | `stop_kontak` | Slave | relay | GPIO 6 |
| `kamar_1` | `lampu` | Slave | dimmer | relay GPIO 7, dimmer channel 1 |
| `kamar_2` | `stop_kontak` | Slave | relay | GPIO 8 |
| `kamar_2` | `lampu` | Slave | dimmer | relay GPIO 9, dimmer channel 1 |
| `dapur` | `lampu` | Slave | dimmer | relay GPIO 10, dimmer channel 2 |
| `dapur` | `blower` | Slave | relay | GPIO 11 |

Slave dimmer memakai zero-cross GPIO 14 dan gate GPIO 15/16.

## ESP-NOW Contract

`DeviceCommandPayload` tetap packed 92 byte. `DeviceStatePayload` tetap packed 98 byte. Internal `requestId` dipakai master untuk ACK/retry dan tidak masuk Firebase.

Master mengirim satu command pada satu waktu. Retry dalam siklus memakai `requestId` sama sehingga duplicate cache slave tidak mengeksekusi hardware dua kali.

Slave mengirim:

- ACK langsung setelah command;
- full snapshot setelah command dimmable;
- boot snapshot setelah link tersedia;
- periodic full snapshot setiap 5 detik.

## Radio Recovery

Master mengikuti channel router Wi-Fi dan broadcast discovery beacon. Slave scan channel 1 sampai 13, mengunci channel beacon, lalu scan ulang setelah link timeout.

Setelah Wi-Fi master reconnect, peer ESP-NOW dan stream Firebase disegarkan.

## Telemetry

Flutter tetap membaca `/device/sensorData`. Saat `environment.connected == false`, temperature dan humidity dinormalisasi menjadi `0` oleh master dan mapper Flutter.

## Verification

Flutter:

```powershell
flutter analyze
flutter test
```

Firmware tidak dibuild atau di-upload pada perubahan ini. Validasi compile dan hardware harus dilakukan terpisah.
