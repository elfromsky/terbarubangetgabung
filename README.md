# Slave Firmware ESP32-S3

Firmware ini menjalankan board slave berbasis `esp32-s3-devkitc-1` untuk menerima command dari master lewat ESP-NOW, mengontrol relay dan dimmer lokal, lalu mengirim ACK dan state report kembali ke master.

Dokumentasi utama repo ini:

- `docs/developer-guide.md`: workflow harian untuk ubah, build, flash, dan validasi code
- `docs/architecture.md`: peta arsitektur dan alur data berdasar code aktif
- `docs/change-checklists.md`: checklist aman untuk jenis perubahan yang sering terjadi

Catatan kerja lama tetap dipisah dan tidak dianggap dokumentasi utama:

- `development-plan.md`
- `current-state.md`
- `slave-repo-checklist.md`

## Stack

- PlatformIO
- Arduino framework untuk ESP32
- ESP-NOW untuk command dan state report
- Relay output
- AC dimmer berbasis zero-cross interrupt

## Struktur Folder Penting

- `src/main.cpp`: boot sequence, main loop, periodic state report
- `src/esp_now_handler.cpp`: receive/send ESP-NOW dan CRC
- `src/room_device_routing.cpp`: mapping `roomKey`/`deviceKey` ke hardware lokal
- `src/relay.cpp`: kontrol relay digital
- `src/dimmer.cpp`: kontrol brightness dimmer
- `platformio.ini`: konfigurasi board dan build
- `docs/`: dokumentasi operasional repo

## Target Board

- Board: `esp32-s3-devkitc-1`
- Framework: `arduino`
- Monitor speed: `115200`

Lihat `platformio.ini` untuk nilai build aktif.

## Command Dasar

Build firmware:

```powershell
pio run
```

Upload firmware:

```powershell
pio run -t upload
```

Buka serial monitor:

```powershell
pio device monitor
```

Kalau board tidak terdeteksi otomatis, cek port yang tersedia:

```powershell
pio device list
```

## Urutan Cepat Saat Mulai Kerja

1. Baca `docs/developer-guide.md`.
2. Baca `docs/architecture.md` bila perubahan menyentuh alur runtime atau contract device.
3. Jalankan `git status --short` untuk cek worktree aktif.
4. Grep simbol atau `roomKey`/`deviceKey` yang akan diubah.
5. Build sebelum dan sesudah perubahan.

## Fakta Penting Saat Ini

- Contract device masih di-hardcode dalam route table di `src/room_device_routing.cpp`.
- Jalur `dapur` aktif sekarang hanya `dapur/lampu` dan `dapur/blower`.
- Relay aktif sekarang berjumlah `8` channel.
- Logika relay di code sekarang active-low. Asumsi wiring `NC-COM` tetap harus diverifikasi di hardware nyata.
- EEPROM sudah dihapus dari codebase ini. State relay dan dimmer sekarang hanya hidup selama runtime board aktif.
- Dokumentasi lama di root bisa berbeda dari code aktif. Saat ragu, code aktif menang.

## Batasan Dokumen Ini

`README.md` ini hanya entry point. Jangan jadikan file ini sebagai satu-satunya referensi untuk perubahan teknis yang rawan. Untuk perubahan nyata, selalu lanjut ke `docs/developer-guide.md` dan `docs/change-checklists.md`.
