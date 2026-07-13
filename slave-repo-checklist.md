# Slave Repo Checklist

## Purpose

Checklist ini dipakai saat mengubah repo slave agar sinkron dengan contract baru di repo master.

Fokus utama:

1. hapus key lama `lampu_1` dan `lampu_2`
2. pakai key final `lampu`
3. pertahankan `dapur/lampu` sebagai device `dimmable`
4. pastikan ACK/report slave tetap cocok dengan payload yang diharapkan master

## Contract Final yang Harus Diikuti Slave

Target minimum untuk jalur `dapur`:

| Room | Device | Capability | Owner |
| --- | --- | --- | --- |
| `dapur` | `lampu` | dimmable | Slave |

Contract payload yang harus tetap cocok dengan master:

- `roomKey`
- `deviceKey`
- `state`
- `brightness`
- `requestId`
- `crc`

ACK/report slave juga harus tetap mengisi:

- `success`
- `errorCode`
- `timestamp`

## Rules Rollout

1. hard cutover langsung
2. jangan dukung alias `lampu_1`
3. jangan dukung alias `lampu_2`
4. semua command/report baru harus pakai `deviceKey = lampu`

## Pre-Change Checklist

Sebelum edit repo slave:

1. baca `README.md`
2. baca `docs/current-state.md`
3. baca `docs/development-plan.md`
4. catat bahwa repo master sudah berubah duluan
5. catat bahwa jika slave masih pakai key lama, hard cutover belum selesai

## Search Checklist

Lakukan grep di repo slave untuk semua referensi ini:

1. `lampu_1`
2. `lampu_2`
3. `dapur`
4. `deviceKey`
5. `roomKey`
6. `brightness`
7. `requestId`
8. `CMD_TYPE_COMMAND`
9. `CMD_TYPE_STATE`
10. `computeXorCRC`

Jika ada file config atau mapping device, grep juga:

1. `lampu`
2. `room`
3. `relay`
4. `dimmer`
5. `ACK`
6. `report`

## File Review Checklist

Di repo slave, cari file yang berperan seperti ini:

1. parser payload ESP-NOW masuk
2. validator `roomKey` dan `deviceKey`
3. router device lokal slave
4. kontrol relay atau dimmer untuk `dapur/lampu`
5. pembuat ACK/report state
6. helper CRC / request matching
7. mapping room-device ke hardware pin atau channel

Kalau nama file berbeda, tetap cari berdasarkan fungsi, bukan nama file.

## Required Code Changes

### 1. Device Key Migration

Harus dilakukan:

1. ganti semua referensi `lampu_1` menjadi `lampu`
2. hapus semua referensi `lampu_2`
3. pastikan tidak ada fallback yang masih menerima key lama

Harus dicek:

1. parser command masuk
2. validator command
3. router internal ke output hardware
4. generator ACK/report state
5. log/debug output

### 2. Dimmable Behavior

`dapur/lampu` harus tetap dimmable.

Harus dicek:

1. brightness `0..100` masih diterima
2. `state = false` memaksa brightness efektif `0` bila desain slave memang mengikuti contract master
3. `state = true` dengan brightness valid tetap mengendalikan output dimmer
4. payload yang bukan object atau brightness di luar range ditolak dengan aman

### 3. ACK / State Report

Harus dilakukan:

1. slave kirim balik `deviceKey = lampu`
2. slave kirim `roomKey = dapur`
3. slave mempertahankan `requestId` dari command masuk saat mengirim ACK yang cocok
4. slave isi `success`, `errorCode`, dan `timestamp` sesuai perilaku aktual

Harus dicek:

1. jangan ada ACK yang masih kirim `lampu_1`
2. jangan ada report spontan yang masih kirim `lampu_2`

### 4. Hardware Mapping

Harus dicek:

1. channel/pin untuk `dapur/lampu` masih benar setelah nama device disederhanakan
2. jika sebelumnya `lampu_1` dan `lampu_2` mewakili dua channel berbeda, putuskan channel final mana yang jadi `lampu`
3. hapus channel kedua jika memang tidak lagi dipakai
4. jangan sisakan routing yatim yang masih menunggu `lampu_2`

Catatan:

Ini titik paling rawan salah asumsi. Pastikan keputusan channel final jelas sebelum edit.

## Validation Checklist

### Parser and Routing

1. command untuk `dapur/lampu` diterima
2. command untuk `dapur/lampu_1` ditolak
3. command untuk `dapur/lampu_2` ditolak
4. command untuk device lain tidak rusak karena perubahan ini

### Dimming

1. brightness `0` menghasilkan output OFF
2. brightness `1..100` menghasilkan level dimming yang benar
3. `state=false` tidak meninggalkan output menyala
4. `state=true` tanpa brightness invalid tidak menyebabkan perilaku liar

### ACK / Report

1. ACK untuk command sukses pakai `deviceKey = lampu`
2. ACK untuk command gagal tetap pakai `deviceKey = lampu`
3. `requestId` yang dibalas sama dengan yang diterima
4. CRC packet keluar valid

### End-to-End with Master

1. master kirim `dapur/lampu`
2. slave mengeksekusi command
3. master menerima ACK yang match
4. master update `/rooms/dapur/lampu`
5. tidak ada timeout palsu karena mismatch key lama

## Failure Signs

Kalau salah satu ini muncul, cek ulang contract slave:

1. master log `Slave ACK timeout`
2. master log `Ignoring unknown room/device command`
3. state Firebase tidak pernah update ke `/rooms/dapur/lampu`
4. ACK slave terlihat sukses tapi master tidak menganggapnya match
5. brightness tidak bekerja walau state ON berhasil

## Post-Change Checklist

Selesai ubah repo slave bila semua ini benar:

1. tidak ada referensi `lampu_1` di jalur `dapur/lampu`
2. tidak ada referensi `lampu_2`
3. semua ACK/report pakai `lampu`
4. dimming tetap jalan
5. test dengan repo master lolos
6. dokumen lokal atau comment yang relevan sudah diperbarui bila perlu

## Suggested Working Order

Urutan aman saat membuka repo slave:

1. grep semua key lama
2. petakan file parser dan ACK
3. tentukan mapping hardware final untuk `dapur/lampu`
4. ubah parser/validator
5. ubah routing hardware
6. ubah ACK/report
7. grep ulang key lama
8. uji slave lokal
9. uji end-to-end dengan master
