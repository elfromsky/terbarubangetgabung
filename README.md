# ESH Flutter

Aplikasi Flutter untuk monitoring telemetry, melihat histori, dan mengontrol perangkat rumah melalui Firebase Realtime Database. Firmware `fullgabung` menjadi gateway Firebase/ESP-NOW master; firmware `fullgabung2` menjadi ESP-NOW slave.

## Urutan Dokumentasi dan Eksekusi

1. Baca dan selesaikan `docs/01-integrasi-esp-now-master-slave.md`.
2. Pastikan acceptance gate integrasi master/slave lulus.
3. Lanjutkan `docs/02-perbaikan-pengembangan-newflutbaru.md`.

Urutan ini wajib karena status command Flutter bergantung pada ACK dan state writeback firmware.

## Arsitektur Singkat

```text
Flutter
  -> Firebase /commands
  -> fullgabung master
  -> ESP-NOW
  -> fullgabung2 slave
  -> ACK/status
  -> fullgabung master
  -> Firebase /rooms
  -> Flutter
```

Flutter tidak terhubung langsung ke ESP-NOW.

## Firebase Path Aktif

- telemetry: `/device/sensorData`
- status perangkat: `/rooms/<roomKey>/<deviceKey>`
- command: `/commands/rooms/<roomKey>/<deviceKey>`
- connection: `/.info/connected`
- history: Firestore collection `sensorLogs`

## Menjalankan Aplikasi

```powershell
flutter pub get
flutter run
```

Konfigurasi Firebase lokal harus tersedia sebelum aplikasi dijalankan. Baris kosong yang sengaja dipertahankan pada `lib/firebase_options.dart` bukan bagian perbaikan otomatis.

## Verifikasi

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

## Batasan Aktif

- `kamar_1/lampu` dan `kamar_2/lampu` berbagi dimmer channel 1 pada slave, sehingga brightness hardware tidak independen.
- `dapur/lampu` memakai dimmer channel 2.
- Firebase write hanya berarti command masuk antrean backend. State perangkat dianggap confirmed setelah `/rooms/...` diperbarui master.
- Status koneksi Firebase bukan status kesehatan gateway atau peer ESP-NOW.
- Deployment rules, auth, release signing, dan validasi hardware dikelola terpisah sesuai lingkungan produksi.
