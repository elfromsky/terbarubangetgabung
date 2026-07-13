# Developer Guide

Dokumen ini jadi pegangan utama untuk kerja harian di repo ini. Fokusnya bukan teori penuh, tapi cara ubah code dengan aman dan cepat.

## Tujuan Repo

Repo ini mengendalikan firmware slave yang:

1. menerima command device dari master lewat ESP-NOW
2. memetakan command ke relay atau dimmer lokal
3. mengirim ACK dan periodic state report kembali ke master
4. menjaga state relay dan dimmer hanya selama runtime board aktif

## Mulai Dalam 5 Menit

Kalau baru masuk lagi ke repo ini setelah jeda, baca file ini dulu:

1. `README.md`
2. `docs/architecture.md`
3. `src/main.cpp`
4. `src/room_device_routing.cpp`
5. `src/esp_now_handler.cpp`

Urutan ini cukup untuk memahami boot flow, routing contract, dan jalur komunikasi utama.

## Workflow Aman Sebelum Edit

Sebelum sentuh code:

1. cek worktree

```powershell
git status --short
```

2. cari semua referensi domain yang akan diubah

Contoh kalau mau ubah nama device:

```powershell
rg "lampu|dapur|deviceKey|roomKey" -n
```

Kalau sedang audit migration key lama, pakai:

```powershell
rg "lampu_1|lampu_2" src docs -n
```

Contoh kalau mau cek apakah masih ada jejak persistence lama:

```powershell
rg "EEPROM|eeprom" src -n
```

3. cek apakah perubahan menyentuh contract lintas repo

Perubahan dianggap lintas repo kalau menyentuh salah satu ini:

- `roomKey`
- `deviceKey`
- struct `DeviceCommandPayload`
- struct `DeviceStatePayload`
- aturan `requestId`
- aturan `crc`
- ekspektasi ACK atau periodic report

Kalau ya, jangan anggap repo ini berdiri sendiri. Perubahan semacam itu hampir pasti perlu sinkronisasi dengan repo master, repo slave lain, atau writer command lain.

## File yang Paling Sering Perlu Dibaca

### `src/main.cpp`

Pakai file ini untuk paham:

- urutan boot
- default runtime saat startup
- kapan snapshot awal dikirim ke master
- kapan periodic full status dikirim

### `src/room_device_routing.cpp`

Pakai file ini untuk paham:

- daftar device yang benar-benar dikenali slave
- device mana yang dimmable dan mana yang state-only
- validasi state dan brightness
- duplicate request handling

Kalau ada bug “command masuk tapi device tidak jalan”, file ini hampir selalu salah satu titik cek pertama.

### `src/esp_now_handler.cpp`

Pakai file ini untuk paham:

- filter MAC master
- validasi panjang payload
- validasi CRC
- cara slave menyimpan command yang baru diterima
- cara ACK/state report dikirim balik

### `src/relay.cpp` dan `src/dimmer.cpp`

Pakai file ini untuk paham:

- mapping output hardware
- logika ON/OFF fisik
- channel dimmer yang dipakai beberapa device
- perilaku default runtime setelah boot

Khusus `src/relay.cpp`, code aktif sekarang memakai active-low. Artinya OFF logis menulis `HIGH`, ON logis menulis `LOW`. Jangan anggap ini otomatis valid terhadap wiring `NC-COM` sebelum diuji di hardware.

Catatan: EEPROM sudah dihapus dari codebase ini. Kalau menemukan asumsi bahwa board memulihkan state lama saat boot, anggap asumsi itu usang sampai terbukti lain di source aktif.

## Workflow Perubahan Harian

Pola kerja aman:

1. tentukan concern yang diubah
2. grep semua pemakaian symbol/domain terkait
3. baca file yang terdampak langsung
4. edit sekecil mungkin
5. build
6. monitor serial atau uji hardware bila perlu
7. grep ulang untuk pastikan tidak ada referensi lama tertinggal
8. update dokumentasi kalau perilaku sistem berubah

Jangan mulai dari edit besar tanpa tahu jalur datanya lebih dulu.

## Build, Upload, Monitor

Build:

```powershell
pio run
```

Upload:

```powershell
pio run -t upload
```

Monitor serial:

```powershell
pio device monitor
```

Kalau perlu monitor setelah upload, jalankan dua langkah terpisah. Jangan asumsikan port serial selalu tetap. `platformio.ini` saat ini tidak memaksa port tertentu.

## Validasi Minimal Setelah Perubahan

Minimal lakukan ini setelah ubah code:

1. `pio run` harus lolos
2. boot log harus muncul normal di serial
3. slave tidak restart loop
4. command valid tetap diterima
5. ACK tetap terkirim
6. periodic report tetap jalan

Tambah validasi sesuai jenis perubahan:

- ubah route table: cek semua `roomKey`/`deviceKey` terdampak
- ubah dimmer: cek brightness `0`, `1`, `100`
- ubah relay logic: cek ON/OFF fisik, bukan hanya log serial
- ubah ESP-NOW payload: cek ukuran struct dan CRC match
- ubah boot behavior: cek power-cycle nyata

## Area Rawan yang Harus Diingat

### Contract device tersebar di beberapa asumsi

Walau route table ada di satu file, dampak contract tidak berhenti di situ. Nama device yang berubah bisa memengaruhi:

- parser di sisi master
- ACK matching
- dashboard atau automation yang menulis command
- ekspektasi operator terhadap hardware channel tertentu

### Dimmable device tidak hanya soal brightness

Untuk device dimmable, state dan brightness punya coupling:

- `state = OFF` dipaksa jadi brightness `0`
- brightness `0` pada device dimmable dianggap OFF
- device state-only dipaksa brightness `100` saat ON

Perubahan kecil di aturan ini bisa mengubah contract yang dilihat master.

### Tidak ada persistence lokal lagi

Pada code aktif sekarang, board tidak memulihkan state lama saat startup. Setelah restart atau power loss, hasil boot bergantung pada default runtime dan command baru dari master.

### Duplicate request handling ada di routing layer

`src/room_device_routing.cpp` punya cache request kecil untuk mencegah eksekusi hardware berulang pada command yang sama. Kalau ada perubahan ke `requestId`, ACK, atau policy retry master, area ini harus ikut ditinjau.

## Kapan Harus Cek Repo Lain

Wajib cek repo lain kalau perubahan menyentuh:

1. nama room atau device
2. payload ESP-NOW
3. arti `state` dan `brightness`
4. ACK matching
5. ekspektasi boot state yang dipakai master atau dashboard setelah restart slave

Kalau perubahan murni lokal, misalnya komentar atau perapihan internal yang tidak mengubah contract, repo lain tidak wajib disentuh.

## Sumber Kebenaran

Prioritas sumber kebenaran:

1. code aktif di `src/`
2. `docs/architecture.md`
3. `docs/change-checklists.md`
4. catatan kerja lama di root repo

Kalau dokumen lama bertabrakan dengan code aktif, ikuti code aktif dan perbarui docs utama.
