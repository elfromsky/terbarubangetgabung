# Architecture

Dokumen ini merangkum perilaku code aktif saat ini. Fokus pada alur runtime, boundary modul, dan titik rawan perubahan.

## Ringkasan Sistem

Board ini adalah slave ESP32-S3 yang menerima command dari satu master ESP-NOW, menjalankan aksi pada hardware lokal, lalu mengirim balik hasil eksekusi atau state periodik.

Komponen utama:

- command receive dan send: `src/esp_now_handler.cpp`
- semantic routing device: `src/room_device_routing.cpp`
- relay control: `src/relay.cpp`
- dimmer control: `src/dimmer.cpp`
- boot dan polling loop: `src/main.cpp`

## Boot Flow

Boot sequence saat ini di `src/main.cpp`:

1. `Serial.begin(115200)` dan log boot
2. `initRelays()` untuk setup pin relay dan state RAM awal
3. `initializeDimmers()` untuk setup pin dimmer, timer, dan zero-cross interrupt
4. `initEspNow()` untuk masuk mode STA, init ESP-NOW, dan add peer master
5. kirim boot snapshot penuh untuk semua device lewat `buildPeriodicStateForDevice()` dan `sendStateToMaster()`
6. masuk loop utama

Implikasi:

- boot state saat ini ditentukan oleh inisialisasi runtime, bukan restore state tersimpan
- sesudah boot, master mendapat snapshot awal sebelum report periodik pertama

## Main Loop

Loop utama di `src/main.cpp` punya dua tugas:

1. proses command yang baru diterima
2. kirim full status periodik setiap `5000` ms

Alur command:

1. `getReceivedCommand()` cek apakah callback receive sudah menyimpan command baru
2. kalau ada, `setCommandPending(false)` dipanggil
3. command dicetak ke serial
4. `applyDeviceCommand()` menjalankan validasi, routing, dan aksi hardware
5. hasil eksekusi dikirim balik lewat `sendStateToMaster()`

Alur periodic status:

1. setiap interval, loop iterasi semua entri route table
2. `buildPeriodicStateForDevice()` membaca state relay dan brightness saat ini
3. state report dikirim satu per satu ke master

## ESP-NOW Layer

`src/esp_now_handler.cpp` menangani boundary komunikasi radio.

Tanggung jawab file ini:

- menetapkan `MASTER_MAC`
- inisialisasi ESP-NOW dan peer master
- menerima packet masuk
- validasi panjang payload command
- validasi type field command
- validasi CRC
- menyimpan command terakhir ke buffer statis
- mengirim ACK atau state report ke master

Karakteristik penting:

- hanya satu command pending yang disimpan pada satu waktu
- filter sumber packet berbasis MAC master
- CRC dihitung sebagai XOR seluruh byte payload kecuali field CRC terakhir

## Payload Contract

Definisi payload ada di `src/esp_now_config.h`.

### `DeviceCommandPayload`

Dipakai untuk command dari master ke slave.

Field utama:

- `type`
- `roomKey`
- `deviceKey`
- `state`
- `brightness`
- `requestId`
- `crc`

Constraint penting:

- struct dipaksa `packed`
- ukuran di-`static_assert` harus `92`
- perubahan field atau panjang string akan memengaruhi kompatibilitas master-slave

### `DeviceStatePayload`

Dipakai untuk ACK dan periodic state report dari slave ke master.

Field utama:

- `type`
- `roomKey`
- `deviceKey`
- `state`
- `brightness`
- `requestId`
- `success`
- `errorCode`
- `timestamp`
- `crc`

Constraint penting:

- struct dipaksa `packed`
- ukuran di-`static_assert` harus `98`
- `requestId` kosong pada periodic report dan diisi pada ACK

## Routing Layer

`src/room_device_routing.cpp` adalah jantung contract lokal board ini.

Isi utamanya:

- route table `roomKey` + `deviceKey` ke `relayId` dan `dimmerChannel`
- penanda `isDimmable`
- validasi state dan brightness
- duplicate request cache
- pembentukan ACK result
- pembentukan periodic state per device

### Route Table Saat Ini

Device saat ini masih di-hardcode. Khusus jalur `dapur`, code aktif saat ini memakai:

- `dapur/lampu`
- `dapur/blower`

Key lama `dapur/lampu_1` dan `dapur/lampu_2` tidak lagi ada di route table aktif.

### Aturan State dan Brightness

Aturan yang berlaku saat ini:

1. `state = OFF` selalu menghasilkan brightness `0`
2. `state = ON` pada device dimmable memakai brightness dari payload
3. brightness di atas `100` ditolak
4. device dimmable dengan brightness `0` dinormalisasi menjadi OFF
5. device state-only dipaksa brightness `100` saat ON

Aturan ini membentuk contract perilaku yang dilihat master.

### Duplicate Cache

Routing layer menyimpan cache kecil ukuran `8` entry untuk `requestId` + `roomKey` + `deviceKey`.

Tujuan:

- mencegah eksekusi hardware ganda pada command yang sama
- tetap bisa mengirim hasil yang sama untuk duplicate request

Kalau master punya retry policy, fitur ini ikut menentukan hasil akhir sistem.

## Relay Layer

`src/relay.cpp` memegang:

- array pin relay
- state relay di RAM
- `initRelays()`
- `setRelayState()`
- `getRelayState()`

Perilaku code aktif sekarang:

- relay diinisialisasi dengan `digitalWrite(..., HIGH)`
- `setRelayState(true)` menulis `LOW`
- log serial menyebut `Active-LOW Mode`
- state relay hanya disimpan di RAM selama board hidup

Makna praktis:

- code aktif sekarang memang active-low, tetapi wiring `NC-COM` tetap harus diverifikasi di hardware nyata
- validasi relay harus selalu cek hardware nyata, bukan hanya komentar atau log lama

## Dimmer Layer

`src/dimmer.cpp` memegang:

- pin zero-cross dan output TRIAC
- dua hardware timer
- ISR zero-cross dan timer
- brightness in-memory per channel

Perilaku penting:

- brightness `1..100` dipetakan ke delay `8600..500` mikrodetik
- brightness `0` mematikan output channel
- brightness hanya hidup di RAM selama board aktif

Coupling hardware penting:

- channel 1 dipakai bersama lampu `kamar_1` dan `kamar_2`
- channel 2 dipakai untuk jalur dapur

Jadi perubahan mapping satu device dimmable bisa berimbas ke ekspektasi wiring atau debugging device lain.

## State Model Saat Ini

Code aktif sekarang tidak punya persistence lokal.

Maknanya:

- state relay disimpan di RAM `relay.cpp`
- brightness dimmer disimpan di RAM `dimmer.cpp`
- restart board menghapus state runtime lama
- master harus mengandalkan boot snapshot baru atau command baru setelah slave hidup kembali

## Error Handling

Error yang ditangani routing layer sekarang:

- unknown device
- invalid state
- invalid brightness

Error dikembalikan lewat field:

- `success`
- `errorCode`
- `timestamp`

Layer radio juga menolak packet yang:

- bukan dari MAC master
- panjangnya tidak cocok
- type field salah
- CRC salah

## Titik Rawan Perubahan

Perubahan di area ini wajib lebih hati-hati:

1. `src/esp_now_config.h`
Perubahan struct bisa memutus kompatibilitas master-slave.

2. `src/room_device_routing.cpp`
Perubahan route table atau aturan normalization bisa memutus contract perilaku.

3. `src/relay.cpp`
Perubahan logika ON/OFF bisa berbeda dengan wiring nyata.

4. `src/dimmer.cpp`
Perubahan timing atau mapping brightness bisa mengubah perilaku listrik nyata.

5. boot behavior setelah restart atau power-cycle
Karena tidak ada persistence lokal, perubahan init runtime langsung memengaruhi kondisi awal sistem.

## Boundary Sumber Kebenaran

Untuk repo ini, source of truth teknis adalah:

1. file di `src/`
2. dokumen ini
3. dokumen operasional di `docs/`
4. catatan lama di root repo

Kalau ada konflik, code aktif menang.
