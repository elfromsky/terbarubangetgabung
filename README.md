# ESH Flutter

Aplikasi Flutter untuk monitoring telemetry, melihat histori, dan mengontrol perangkat rumah melalui Firebase Realtime Database. Firmware `mastergabung` menjadi gateway Firebase/ESP-NOW master; firmware `slavegabung` menjadi ESP-NOW slave.

## Urutan Dokumentasi dan Eksekusi

1. Baca dan selesaikan `docs/01-integrasi-esp-now-master-slave.md`.
2. Pastikan acceptance gate integrasi master/slave lulus.
3. Lanjutkan `docs/02-perbaikan-pengembangan-newflutbaru.md`.

Urutan ini wajib karena status command Flutter bergantung pada ACK dan state writeback firmware.

## Arsitektur Singkat

```text
Flutter
  -> Firebase /commands
  -> mastergabung
  -> ESP-NOW
  -> slavegabung
  -> ACK/status
  -> mastergabung
  -> Firebase /rooms
  -> Flutter
```

Flutter tidak terhubung langsung ke ESP-NOW.

## Firebase Path Aktif

- telemetry: `/device/sensorData`
- status aktual perangkat: `/rooms/<roomKey>/tools/<deviceKey>`
- desired state: `/commands/rooms/<roomKey>/tools/<deviceKey>`
- connection: `/.info/connected`
- history: Firestore collection `sensorLogs`

## Menjalankan Aplikasi

```powershell
flutter pub get
flutter run
```

Konfigurasi Firebase lokal harus tersedia sebelum aplikasi dijalankan. Baris kosong yang sengaja dipertahankan pada `lib/firebase_options.dart` bukan bagian perbaikan otomatis.

Prosedur pendaftaran perangkat (custom claim `owner`/`controller`) dan siklus penyegaran token dijelaskan di `docs/firebase-security-provisioning.md`.

## Verifikasi

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

## Batasan Aktif

- `kamar_1/lampu` dan `kamar_2/lampu` berbagi dimmer channel 1 pada slave, sehingga brightness hardware tidak independen.
- ON/OFF kedua lampu kamar tetap independen. Perubahan brightness salah satunya ditulis atomik untuk keduanya.
- `dapur/lampu` memakai dimmer channel 2.
- `/commands` menyimpan desired state terbaru dan tidak dihapus master. State perangkat dianggap aktual setelah `/rooms/...` diperbarui master.
- UI ON/OFF dan brightness hanya mengikuti `/rooms`; write `/commands` hanya menampilkan pending.
- Dimmer ON memakai brightness `1..100`. Saat OFF, brightness terakhir tetap disimpan.
- Telemetry environment yang disconnected dinormalisasi menjadi temperature dan humidity `0`.
- Status koneksi Firebase bukan status kesehatan gateway atau peer ESP-NOW.
- Deployment rules, auth, release signing, dan validasi hardware dikelola terpisah sesuai lingkungan produksi.
