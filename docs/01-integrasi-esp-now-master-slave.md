# Integrasi Flutter, ESP-NOW Master, dan ESP-NOW Slave

## Tujuan

Dokumen ini menjadi kontrak integrasi untuk tiga codebase:

- `newflutbaru`: aplikasi Flutter yang membaca telemetry/status dan menulis command melalui Firebase.
- `fullgabung`: ESP32-S3 master yang terhubung ke Wi-Fi/Firebase, mengontrol perangkat lokal, dan menjadi gateway ESP-NOW.
- `fullgabung2`: ESP32-S3 slave yang menerima command ESP-NOW, mengontrol relay/dimmer, lalu mengirim ACK dan status.

Pekerjaan dalam dokumen ini wajib selesai dan lolos acceptance gate sebelum pekerjaan perbaikan/pengembangan `newflutbaru` pada `docs/02-perbaikan-pengembangan-newflutbaru.md` dimulai.

## Batasan Tetap

- `peerInfo.channel = 0` dipertahankan pada master dan slave sesuai keputusan pemilik proyek.
- Master dan slave beroperasi pada channel radio Wi-Fi 6. Nilai `0` pada peer berarti mengikuti channel aktif interface, bukan mengubah keputusan channel operasi.
- MAC slave yang dipakai master: `68:B6:B3:2E:42:4C`.
- MAC master yang dipakai slave: `10:B4:1D:C9:10:B0`.
- Baris konfigurasi yang sengaja kosong pada `newflutbaru/lib/firebase_options.dart` tidak diubah dan tidak dianggap defect.
- Flutter tidak memakai ESP-NOW secara langsung. Firebase menjadi boundary antara Flutter dan master.

## Arsitektur

```text
newflutbaru
  | RTDB command: /commands/rooms/<roomKey>/<deviceKey>
  v
Firebase Realtime Database
  |
  v
fullgabung (master)
  |-- device owner Master: kontrol relay lokal
  |-- device owner Slave: DeviceCommandPayload via ESP-NOW
  v
fullgabung2 (slave)
  | kontrol relay/dimmer
  | DeviceStatePayload ACK/report via ESP-NOW
  v
fullgabung (master)
  | RTDB confirmed state: /rooms/<roomKey>/<deviceKey>
  v
newflutbaru
```

## Kontrak Device

| Room | Device | Owner | Capability | Hardware |
| --- | --- | --- | --- | --- |
| `teras` | `lampu` | Master | state-only | relay master pin 21 |
| `teras` | `sanyo` | Master | state-only | relay master pin 5 |
| `lorong` | `stop_kontak` | Slave | state-only | relay 1, pin 38 |
| `lorong` | `blower` | Slave | state-only | relay 2, pin 39 |
| `kamar_1` | `stop_kontak` | Slave | state-only | relay 3, pin 40 |
| `kamar_1` | `lampu` | Slave | dimmable | relay 4, dimmer channel 1 |
| `kamar_2` | `stop_kontak` | Slave | state-only | relay 5, pin 16 |
| `kamar_2` | `lampu` | Slave | dimmable | relay 6, dimmer channel 1 |
| `dapur` | `lampu` | Slave | dimmable | relay 7, dimmer channel 2 |
| `dapur` | `blower` | Slave | state-only | relay 8, pin 11 |

`kamar_1/lampu` dan `kamar_2/lampu` sengaja berbagi dimmer channel 1. Konsekuensinya, keduanya tidak mempunyai brightness hardware independen. Command brightness ke salah satu kamar mengubah output channel yang sama. Firebase tetap mempunyai status per perangkat, sehingga master harus menerima periodic report untuk menjaga status tetap dekat dengan kondisi hardware.

## Kontrak Firebase

### Command state-only

Path:

```text
/commands/rooms/<roomKey>/<deviceKey>
```

Payload:

```json
true
```

atau:

```json
{"state": true}
```

### Command dimmable

```json
{
  "state": true,
  "brightness": 75
}
```

Aturan:

- `state` hanya ON/OFF yang didukung parser.
- `brightness` harus integer `0..100`.
- `state=false` dinormalisasi menjadi brightness `0`.
- brightness `0` pada perangkat dimmable dinormalisasi menjadi OFF.

### Confirmed state

State-only:

```text
/rooms/teras/lampu = true
```

Dimmable:

```json
/rooms/dapur/lampu = {
  "state": true,
  "brightness": 75
}
```

Command Firebase bukan bukti aktuator sudah berubah. Untuk perangkat slave, state baru dianggap confirmed setelah master menerima ACK yang valid dan menulis `/rooms/...`.

## Kontrak ESP-NOW

### Command master ke slave

`DeviceCommandPayload` packed, tepat 92 byte:

| Field | Ukuran | Aturan |
| --- | ---: | --- |
| `type` | 1 | `1` |
| `roomKey` | 24 | null-terminated |
| `deviceKey` | 32 | null-terminated |
| `state` | 1 | `0` atau `1` |
| `brightness` | 1 | `0..100` |
| `requestId` | 32 | opaque ID, echoed oleh ACK |
| `crc` | 1 | XOR seluruh byte sebelumnya |

### ACK/report slave ke master

`DeviceStatePayload` packed, tepat 98 byte:

| Field | Ukuran | Aturan |
| --- | ---: | --- |
| `type` | 1 | `2` |
| `roomKey` | 24 | canonical key |
| `deviceKey` | 32 | canonical key |
| `state` | 1 | final state |
| `brightness` | 1 | final brightness |
| `requestId` | 32 | sama dengan command; kosong untuk periodic report |
| `success` | 1 | `1` sukses, `0` gagal |
| `errorCode` | 1 | `0..5` |
| `timestamp` | 4 | `millis()` slave |
| `crc` | 1 | XOR seluruh byte sebelumnya |

Error code:

| Nilai | Arti |
| ---: | --- |
| 0 | OK |
| 1 | unknown device |
| 2 | invalid state |
| 3 | invalid brightness |
| 4 | invalid CRC |
| 5 | hardware failure |

## Aturan Radio dan Peer

- Master memakai `WIFI_IF_STA` karena Wi-Fi/Firebase dan ESP-NOW berbagi interface STA.
- Slave memakai `WIFI_IF_STA`.
- Kedua peer mempertahankan `peerInfo.channel = 0`.
- Access point/radio operasi ditetapkan pada channel 6.
- Jika channel aktif master atau slave bukan 6, peer dapat terdaftar tetapi packet dapat gagal terkirim.
- Master hanya menerima ACK/report dari `SLAVE_MAC_ADDRESS`.
- Slave hanya menerima command dari `MASTER_MAC`.
- Enkripsi ESP-NOW belum aktif; XOR CRC hanya integrity check, bukan autentikasi/enkripsi.

## Reliability

### Receive queue master

Slave mengirim delapan periodic state. Master tidak boleh menyimpan hanya packet terakhir. Firmware master memakai bounded receive queue agar ACK dan report berurutan tidak saling menimpa.

### Source validation

Master menolak packet dari MAC selain slave. Slave sudah menolak packet dari MAC selain master.

### Critical section

Callback hanya menyalin packet ke buffer. CRC, routing, serial output, dan operasi Firebase dilakukan di main loop di luar critical section.

### Periodic report

Slave tidak mengirim delapan packet sekaligus tanpa pacing. Report dikirim bertahap agar radio dan receive queue master dapat memproses seluruh device.

### Shared dimmer

Saat perangkat dimmable OFF, relay perangkat tersebut dimatikan. Brightness channel dimmer hanya dipaksa `0` jika tidak ada relay lain pada shared channel yang masih ON. Jika salah satu lampu kamar tetap ON, dimmer channel 1 tetap memakai brightness terakhir yang diterapkan.

## Urutan Implementasi

1. Sinkronkan mapping dimmer slave:
   - channel 1: `kamar_1/lampu`, `kamar_2/lampu`;
   - channel 2: `dapur/lampu`.
2. Tambahkan filter MAC dan bounded receive queue pada master.
3. Pindahkan operasi Firebase keluar critical section.
4. Pace boot snapshot dan periodic report slave.
5. Build `fullgabung`.
6. Build `fullgabung2`.
7. Flash master dan slave.
8. Verifikasi serial/radio dasar.
9. Uji command Firebase sampai confirmed state Flutter.
10. Setelah acceptance gate lulus, mulai dokumen/perbaikan nomor 2.

## Build

Master:

```powershell
cd fullgabung
pio run
```

Slave:

```powershell
cd fullgabung2
pio run
```

Build sukses hanya membuktikan source dapat dikompilasi. Build tidak membuktikan MAC, channel radio, wiring active-low, zero-cross, Firebase rules, atau kondisi aktuator fisik benar.

## Test Matrix

### Radio dasar

1. Boot master dan slave.
2. Pastikan log kedua board menunjukkan ESP-NOW initialized dan peer registered.
3. Kirim `dapur/lampu` ON brightness 50.
4. Pastikan slave menerima command dengan `room=dapur`, `device=lampu`.
5. Pastikan master menerima ACK dengan request ID sama.

### Device master

- `teras/lampu`: OFF, ON, OFF.
- `teras/sanyo`: OFF, ON, OFF.
- Verifikasi logical state dan beban fisik, bukan log saja.

### Device slave state-only

- Uji setiap relay slave ON/OFF.
- Pastikan relay active-low menghasilkan kondisi fisik sesuai wiring.
- Pastikan `/rooms/...` berubah setelah ACK.

### Device slave dimmable

Untuk setiap route, uji brightness `0`, `1`, `50`, `100`, lalu OFF:

- `kamar_1/lampu` mengubah dimmer channel 1.
- `kamar_2/lampu` mengubah dimmer channel 1.
- `dapur/lampu` mengubah dimmer channel 2.
- Pastikan channel dapur tidak mengubah lampu kamar.
- Pastikan channel kamar tidak mengubah lampu dapur.

### Input invalid

- brightness `101`: ditolak.
- state selain `0/1`: ditolak.
- room/device tidak dikenal: ditolak.
- CRC salah: packet diabaikan.
- packet dari MAC asing: diabaikan.

### Recovery

- Restart slave: seluruh state boot dilaporkan kembali.
- Restart master: periodic report mengisi ulang `/rooms`.
- Putus Wi-Fi master lalu sambungkan kembali: Firebase dan ESP-NOW kembali berfungsi pada channel operasi yang sama.
- Kirim command saat slave offline: command timeout dan UI tidak boleh menganggap state confirmed.

## Acceptance Gate Nomor 1

Integrasi dinyatakan selesai hanya jika:

- kedua firmware lolos `pio run`;
- MAC pada source cocok dengan board fisik;
- master dan slave aktif pada channel radio 6;
- `peerInfo.channel = 0` tetap dipertahankan;
- semua route device sesuai tabel;
- ACK valid diterima untuk setiap command slave;
- delapan periodic report diproses tanpa kehilangan packet;
- Firebase command dihapus setelah hasil diproses;
- `/rooms/...` mencerminkan state terkonfirmasi;
- wiring relay dan mapping dimmer lulus verifikasi fisik;
- failure/timeout tidak ditampilkan sebagai keberhasilan perangkat.

## Troubleshooting

| Gejala | Pemeriksaan |
| --- | --- |
| peer registered tetapi send gagal | channel aktif master/slave, MAC peer, interface STA |
| master selalu ACK timeout | MAC, source filter, CRC, receive queue, slave power |
| hanya status device terakhir muncul | pacing report dan receive queue master |
| dapur mengubah kamar | route dimmer harus dapur channel 2 |
| kamar mengubah dapur | route kamar harus channel 1 |
| command Firebase masuk tetapi relay tidak berubah | owner routing, route table, relay active-low, ACK error |
| UI berubah tetapi hardware tidak | optimistic UI belum dikonfirmasi ACK/status |
| monitoring berjalan tetapi history kosong | telemetry ada di RTDB, sedangkan history membaca Firestore |
