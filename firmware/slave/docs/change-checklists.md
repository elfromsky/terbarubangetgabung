# Change Checklists

Dokumen ini berisi checklist operasional untuk perubahan yang paling rawan di repo ini. Pakai checklist sesuai jenis perubahan, bukan asumsi umum.

## Checklist Umum Sebelum Ubah Apa Pun

1. cek worktree dengan `git status --short`
2. grep simbol, key, atau file yang terdampak
3. baca file pemilik behavior itu, jangan hanya file pemanggilnya
4. tentukan apakah perubahan lokal atau lintas repo
5. build baseline bila perlu

## Ubah `roomKey` atau `deviceKey`

Area wajib cek:

1. `src/room_device_routing.cpp`
2. log serial di `src/main.cpp`
3. ACK content hasil `applyDeviceCommand()`
4. periodic report hasil `buildPeriodicStateForDevice()`
5. repo master dan sistem penulis command lain

Langkah aman:

1. grep semua key lama dan baru
2. ubah route table
3. ubah validasi atau asumsi terkait bila ada
4. grep ulang key lama
5. build
6. uji command valid
7. uji command lama ditolak bila memang hard cutover
8. uji ACK dan periodic report menampilkan key baru

Failure sign:

- command diterima radio tapi dianggap unknown device
- ACK timeout di sisi master
- state report tidak muncul di path yang diharapkan

Catatan migration key:

- kalau target final `dapur/lampu`, maka `dapur/lampu_1` dan `dapur/lampu_2` harus ditolak oleh route aktif

## Ubah Relay Mapping atau Logika ON/OFF

Area wajib cek:

1. `src/relay.h`
2. `src/relay.cpp`
3. entri route table yang memakai relay terkait
4. wiring nyata di hardware

Langkah aman:

1. cek pin dan relay ID yang dipakai sekarang
2. cek apakah device terkait juga tersambung ke dimmer
3. ubah mapping atau logika output
4. build
5. uji ON/OFF lewat command nyata
6. verifikasi kondisi fisik beban, bukan hanya log serial
7. power-cycle bila perubahan memengaruhi boot behavior

Failure sign:

- log bilang OFF tapi beban masih menyala
- pin benar di code tapi channel hardware salah
- state report tidak cocok dengan kondisi listrik nyata

Catatan active-low:

- untuk code active-low, target logika adalah `LOW = ON` dan `HIGH = OFF`
- kalau wiring diasumsikan `NC-COM`, status OFF logis wajib dibuktikan sebagai OFF fisik lewat uji hardware

## Ubah Dimming Behavior

Area wajib cek:

1. `src/dimmer.cpp`
2. `src/dimmer.h`
3. `src/room_device_routing.cpp`
4. device yang berbagi channel dimmer sama

Langkah aman:

1. cek channel mana yang dipakai device target
2. cek mapping brightness dan normalization di routing layer
3. ubah logic secukupnya
4. build
5. uji brightness `0`
6. uji brightness `1`
7. uji brightness `100`
8. uji `state=false` dan `state=true`

Failure sign:

- brightness `0` tidak benar-benar OFF
- brightness kecil tidak stabil
- device lain yang berbagi channel ikut terpengaruh tak terduga

## Ubah Payload ESP-NOW

Area wajib cek:

1. `src/esp_now_config.h`
2. `src/esp_now_handler.cpp`
3. semua producer dan consumer payload di repo pasangan

Langkah aman:

1. tentukan apakah perubahan backward-compatible atau hard cutover
2. ubah struct payload
3. cek `static_assert` size
4. cek CRC calculation masih benar
5. build
6. uji receive command
7. uji ACK dan periodic report
8. sinkronkan semua repo pasangan sebelum rollout penuh

Failure sign:

- packet masuk diabaikan walau radio aktif
- CRC mismatch
- struct size tidak sama antar repo
- ACK tidak bisa diparse sisi master

## Hapus Persistence Lokal

Checklist ini dipakai untuk verifikasi setelah EEPROM removal atau bila nanti ada jejak persistence lain yang ingin dibersihkan.

Area wajib cek:

1. `src/main.cpp`
2. `src/relay.cpp`
3. `src/dimmer.cpp`
4. semua include dan symbol persistence lama

Langkah aman:

1. grep semua referensi `EEPROM` dan `eeprom`
2. pastikan tidak ada init, restore, validate, clear, atau write path persistence tersisa
3. build
4. boot board dari power-on bersih
5. cek semua output mulai dari default runtime yang diinginkan
6. cek snapshot boot yang dikirim ke master tetap konsisten
7. power-cycle beberapa kali untuk verifikasi tidak ada asumsi persistence tersisa

Perubahan perilaku yang harus diakui:

- state relay tidak dipulihkan lagi saat boot
- brightness dimmer tidak dipulihkan lagi saat boot
- hasil restart bergantung penuh pada default runtime dan command baru dari master

Failure sign:

- build gagal karena include atau fungsi persistence lama tertinggal
- boot state tidak sesuai ekspektasi baru
- master salah menganggap state lama masih berlaku setelah reboot slave

## Ubah Boot Behavior

Area wajib cek:

1. `src/main.cpp`
2. `src/relay.cpp`
3. `src/dimmer.cpp`

Langkah aman:

1. definisikan target state saat boot secara eksplisit
2. cek urutan init relay, dimmer, dan snapshot boot
3. build
4. flash board
5. uji cold boot
6. uji reset button
7. uji power loss lalu restore listrik

Failure sign:

- kondisi fisik output berbeda antara cold boot dan reset
- snapshot boot tidak mewakili state nyata

## Uji Akhir Minimum Setelah Perubahan Penting

1. `pio run` lolos
2. serial boot normal
3. command valid dieksekusi
4. ACK terkirim
5. periodic report tetap jalan
6. state report cocok dengan kondisi hardware
7. tidak ada referensi lama tertinggal dari grep akhir

## Perintah Grep Berguna

Contract device:

```powershell
rg "roomKey|deviceKey|lampu|blower|stop_kontak|kamar_1|kamar_2|dapur|lorong" src -n
```

ESP-NOW contract:

```powershell
rg "DeviceCommandPayload|DeviceStatePayload|requestId|crc|ESPNOW_" src -n
```

Persistence:

```powershell
rg "EEPROM|eeprom" src -n
```

Relay dan dimmer:

```powershell
rg "RELAY_|DIMMER_|setRelayState|getRelayState|setDimmerBrightness|getDimmerBrightness" src -n
```
