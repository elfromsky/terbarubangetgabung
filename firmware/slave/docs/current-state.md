# Current State

## Purpose

Dokumen ini memisahkan tiga hal:

1. arsitektur committed yang sudah tampak stabil
2. perubahan lokal yang sedang terlihat di worktree
3. perubahan berikutnya yang diminta, tapi belum final diterapkan

## Committed Architecture Snapshot

Snapshot ini berdasar file yang ada dan histori commit terbaru.

### Runtime Core

- `main.cpp` mengatur boot, polling, dan upload periodik
- WiFi/NTP/Firebase bootstrap dipisah dari parser command
- telemetry dipisah dari command routing
- master/slave dibedakan lewat `DeviceOwner`

### Firebase Paths in Use

Telemetry:

- `/device/sensorData/environment`
- `/device/sensorData/power`
- `/device/sensorData/timestamp`
- `/device/sensorData/unix_time`
- `/device/sensorData/system`

Command stream:

- `/commands`
- contract utama: `/commands/rooms/<roomKey>/<deviceKey>`

State writeback:

- `/rooms/<roomKey>/<deviceKey>`

### Device Contract Seen in Current Code

| Room | Device | Capability | Owner |
| --- | --- | --- | --- |
| `teras` | `lampu` | state-only | Master |
| `teras` | `sanyo` | state-only | Master |
| `lorong` | `blower` | state-only | Slave |
| `lorong` | `stop_kontak` | state-only | Slave |
| `kamar_1` | `lampu` | dimmable | Slave |
| `kamar_1` | `stop_kontak` | state-only | Slave |
| `kamar_2` | `lampu` | dimmable | Slave |
| `kamar_2` | `stop_kontak` | state-only | Slave |
| `dapur` | `blower` | state-only | Slave |
| `dapur` | `lampu` | dimmable | Slave |

## Observed Local Changes

Perubahan ini terlihat di worktree sekarang dan belum dianggap status final proyek.

### 1. Config Style Changed

File terdampak:

- `include/firebase_config.h`
- `include/wifi_config.h`
- `include/firebase_config.example.h` terhapus
- `include/wifi_config.example.h` terhapus

Makna:

- repo bergerak dari pola `.local.h` ke macro langsung di file utama
- setup lokal jadi lebih cepat, tapi pemisahan secret melemah

### 2. Firebase Command Loop Wrapper Added

File terdampak:

- `src/wifi_firebase.cpp`
- `include/wifi_firebase.h`
- `src/main.cpp`

Makna:

- loop command sekarang diringkas ke `checkFirebaseCommands()`
- `main.cpp` lebih bersih karena tidak lagi memanggil `FirebaseLoop()` dan `processSlaveCommunication()` secara terpisah

### 3. Command Parser More Flexible

File terdampak:

- `src/firebase_command_router.cpp`

Makna:

- state-only command bisa dibaca dari bool/int/string/object
- suffix `/state` pada path command bisa diterima
- nested path di bawah device selain `/state` ditolak

### 4. Relay State Tracking Improved

File terdampak:

- `src/relay.cpp`
- `include/relay.h`

Makna:

- state logical relay sekarang disimpan dalam boolean internal
- helper generik `isMasterRelayDevice`, `setMasterRelayState`, `getMasterRelayState` sudah ada
- rename device master ke `lampu` dan active-low relay sekarang sudah diterapkan di repo master

### 5. Board Serial Port Updated

File terdampak:

- `platformio.ini`

Makna:

- upload dan monitor pindah dari `COM7` ke `COM17`
- USB flags tambahan diaktifkan

## Planned Changes Requested

Perubahan ini sebagian sudah diterapkan di repo master. Bagian yang tersisa harus dianggap target pengembangan berikutnya.

### Device Naming Hard Cutover

Target final:

| Room | Device | Capability | Owner |
| --- | --- | --- | --- |
| `teras` | `lampu` | state-only | Master |
| `teras` | `sanyo` | state-only | Master |
| `dapur` | `lampu` | dimmable | Slave |

Perubahan eksplisit:

1. rename device sudah diterapkan di repo master
2. rollout langsung total masih perlu sinkronisasi repo slave dan writer command
3. tidak ada compatibility alias di repo master

### Relay Behavior Change

Target final:

1. relay master sudah diperlakukan active-low di kode
2. wiring dianggap `NC-COM`
3. OFF logis harus tetap diverifikasi sebagai OFF fisik di hardware

## Cross-Repo Dependency Risk

Sudah diketahui bahwa `dapur` slave ada di repo lain.

Berarti perubahan nama device tidak cukup di repo ini saja.

Minimal area yang harus sinkron lintas sistem:

1. parser command di repo ini
2. state writeback Firebase di repo ini
3. parser/slave ACK/report di repo slave
4. dashboard/app/automation yang menulis ke `/commands`

Kalau salah satu sistem lain masih pakai `lampu_1` atau `lampu_2`, hard cutover bisa gagal walau repo master sudah benar.

## Known Limitations Saat Ini

1. contract room/device masih di-hardcode di beberapa modul
2. owner routing berbasis room, belum tabel contract terpusat
3. hanya satu pending command slave yang bisa aktif
4. config lokal sekarang raw macro di file utama, bukan pemisahan secret yang lebih aman
5. dokumentasi repo belum ikut git karena `*.md` di-ignore
6. perilaku `NC-COM` belum tervalidasi di hardware walau active-low sudah tercermin di kode

## Validation Checklist for Next Change

Sebelum menyatakan perubahan berikutnya selesai, cek:

1. `teras/lampu` ON/OFF bekerja
2. `teras/sanyo` ON/OFF bekerja
3. `dapur/lampu` menerima payload dimmable yang benar
4. repo slave lain sudah pakai key `lampu`
5. command writer Firebase sudah pakai key `lampu`
6. relay OFF saat boot sesuai hardware nyata
7. `allRelaysOff()` mematikan beban secara nyata
8. ACK/report slave tetap update Firebase dengan nama baru
