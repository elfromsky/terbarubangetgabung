# Development Plan

## Purpose

Dokumen ini menjadi plan kerja yang bisa terus diubah untuk perubahan dan pengembangan codebase. Isi plan dibagi antara pekerjaan dekat, stabilisasi, dan arah refactor lanjut.

## Planned Changes Now

### 1. Simplify Device Naming

Tujuan:

- hapus `lampu_2` pada `teras`
- hapus `lampu_2` pada `dapur`
- ganti `lampu_1` menjadi `lampu` pada `teras`
- ganti `lampu_1` menjadi `lampu` pada `dapur`
- `dapur/lampu` tetap dimmable

Target contract final minimum:

| Room | Device | Capability | Owner |
| --- | --- | --- | --- |
| `teras` | `lampu` | state-only | Master |
| `teras` | `sanyo` | state-only | Master |
| `dapur` | `lampu` | dimmable | Slave |

Status:

- sudah diterapkan di repo master

Catatan rollout tersisa:

- hard cutover langsung
- tidak ada alias sementara untuk key lama
- semua penulis command dan slave repo harus sinkron serentak

### 2. Change Relay Logic to Active-Low

Status:

- sudah diterapkan di repo master

Tujuan yang tersisa:

- verifikasi default init mewakili OFF fisik di hardware
- verifikasi `allRelaysOff()` tetap berarti OFF logis dan OFF fisik

### 3. Validate `NC-COM` Wiring Assumption

Tujuan:

- verifikasi kondisi beban saat boot
- verifikasi kondisi beban saat relay OFF logis
- verifikasi kondisi beban saat power reset/trip

Ini tidak bisa selesai hanya dari code review. Perlu uji hardware nyata.

### 4. Cross-Repo Synchronization

Tujuan:

- sinkronkan repo master ini dengan repo slave lain
- sinkronkan app/dashboard/automation yang menulis path Firebase

Minimal yang harus sama di semua sistem:

- `roomKey`
- `deviceKey`
- payload `state`
- payload `brightness`
- path Firebase command dan state

## Implementation Order

Urutan yang direkomendasikan:

1. audit perubahan lokal aktif agar tidak tabrakan dengan kerja lain
2. verifikasi `initRelays()` dan `allRelaysOff()` di hardware nyata
3. cek semua path writeback Firebase pakai nama baru
4. sinkronkan repo slave lain
5. sinkronkan writer command Firebase
6. uji end-to-end command, ACK, dan telemetry
7. rapikan dokumentasi bila ada perubahan desain selama implementasi

## Technical Impact Map

### Repo Ini

File prioritas tinggi:

1. `src/firebase_command_router.cpp`
2. `src/relay.cpp`
3. `include/relay.h`
4. kemungkinan `src/esp_now_protocol.cpp` bila perlu catatan owner/contract tambahan
5. dokumentasi lokal

### Repo Slave Lain

Hal yang perlu diubah atau diverifikasi:

1. parsing `deviceKey`
2. payload ACK/state report
3. device routing internal slave
4. writeback atau log yang masih refer key lama

### Firebase / Dashboard / Automation

Hal yang perlu diubah atau diverifikasi:

1. writer command ke `/commands/rooms/...`
2. pembaca state di `/rooms/...`
3. automation yang masih pakai key lama

## Risks

### Functional Risks

1. command gagal karena repo slave masih expect key lama
2. dashboard menulis path lama, lalu command diabaikan
3. writeback state ke key baru membuat UI lama terlihat "mati"

### Electrical Risks

1. active-low di kode benar tetapi wiring nyata bisa tetap menyalakan beban saat boot
2. asumsi `NC-COM` salah lalu OFF logis tidak sama dengan OFF fisik
3. fail-safe trip tidak mematikan beban seperti yang diharapkan

### Maintenance Risks

1. hardcode device contract makin sulit dijaga saat room/device bertambah
2. config file tanpa `.local.h` memudahkan secret bocor saat commit manual
3. dokumen lokal bisa ketinggalan jika tidak di-update setelah perubahan besar

## Validation Checklist

### Firmware Master

1. `teras/lampu` command ON/OFF valid
2. `teras/sanyo` command ON/OFF valid
3. state writeback `teras/lampu` benar
4. command writer eksternal tidak lagi memakai key lama

### Firmware Slave

1. `dapur/lampu` command dimmable diterima
2. brightness `0..100` diproses benar
3. ACK/report slave kirim `deviceKey = lampu`
4. key lama tidak lagi dipakai

### Hardware

1. semua relay OFF saat boot
2. semua relay OFF saat `allRelaysOff()`
3. ON/OFF software cocok dengan kondisi beban nyata
4. reset board tidak memicu kondisi berbahaya

### Firebase End-to-End

1. command baru masuk dari `/commands/rooms/...`
2. command selesai dihapus dari queue
3. state balik ke `/rooms/...`
4. telemetry tetap jalan selama perubahan command berlangsung

## Planned Improvements Later

### 1. Centralize Device Contract

Masalah saat ini:

- daftar device tersebar di beberapa file

Target refactor:

- buat satu tabel contract device terpusat
- metadata minimal:
  - room
  - device key
  - owner
  - capability
  - hardware mapping

Manfaat:

- lebih sedikit duplikasi
- risiko mismatch antar modul turun

### 2. Decouple Command Parsing from Device Routing

Masalah saat ini:

- `firebase_command_router.cpp` memegang terlalu banyak rule domain

Target refactor:

- parser payload terpisah dari rule validasi contract
- router device terpisah dari writeback Firebase

### 3. Improve Secret Handling

Masalah saat ini:

- config sensitif berada di file utama yang mudah ikut commit

Target refactor:

- hidupkan lagi pola `*.local.h`, atau
- generate config lokal dari environment/tooling build

### 4. Improve Observability

Target:

- log lebih konsisten untuk command master
- log lebih konsisten untuk ACK timeout slave
- log yang mudah dibaca saat migrasi contract device

## Open Questions

Pertanyaan yang masih perlu dijawab saat pengembangan lanjut:

1. apakah ada dashboard atau automation lain di luar yang sudah diketahui?
2. apakah semua relay memang harus OFF saat boot, tanpa pengecualian?
3. apakah owner routing akan tetap berbasis room, atau nanti per-device?
4. apakah jumlah room/device akan bertambah cukup banyak hingga perlu konfigurasi terpusat?
5. apakah file contoh config ingin dihidupkan lagi untuk onboarding developer lain?
