# Perbaikan dan Pengembangan `newflutbaru`

## Tujuan

Dokumen ini menjadi baseline perbaikan aplikasi Flutter setelah integrasi `newflutbaru` → Firebase → `fullgabung` master → `fullgabung2` slave disinkronkan. Prioritas utama ialah correctness status perangkat, lifecycle stream, failure handling, histori, dan reproducible verification.

Dokumen integrasi yang harus dibaca lebih dahulu: `docs/01-integrasi-esp-now-master-slave.md`.

## Batasan

- `newflutbaru/lib/firebase_options.dart` sengaja mempunyai beberapa nilai kosong. File tersebut tidak diubah dan nilai kosong tidak dianggap defect.
- Konfigurasi serta deployment Firebase dinyatakan sudah pasti oleh pemilik proyek. `database.rules.json` dan `firestore.rules` tidak diubah dalam pekerjaan ini.
- Flutter tetap memakai Firebase sebagai transport. Tidak ditambah BLE, MQTT, HTTP lokal, atau plugin ESP-NOW.
- Target minimum pekerjaan ini ialah Android. Dukungan desktop tidak diperluas tanpa kebutuhan nyata.
- Tidak dilakukan migrasi state management, dependency major upgrade, atau arsitektur berlapis besar.
- `peerInfo.channel = 0` pada firmware bukan bagian perbaikan Flutter dan tetap dipertahankan.

## Arsitektur Aktif

```text
UI
  MonitoringPage + ControlPage
  HistoryPage
       |
       v
BLoC
  MonitoringBloc
  HistoryBloc
       |
       v
FirebaseService
  RTDB: telemetry, connection, rooms, commands
  Firestore: sensorLogs
```

Boundary aplikasi:

- telemetry: `device/sensorData`;
- koneksi client: `.info/connected`;
- state aktuator terkonfirmasi: `rooms`;
- command: `commands/rooms/<roomKey>/<deviceKey>`;
- histori canonical: Firestore collection `sensorLogs` dengan field `timestamp`, `power`, dan `environment`.

Jalur `energyData` dianggap legacy sampai terbukti masih dipakai sistem eksternal. Jalur tersebut tidak dikembangkan lebih lanjut.

## Temuan dan Prioritas

### P0 — Correctness dan reliability

1. Firebase initialization failure hanya dicetak, tetapi aplikasi tetap membangun service Firebase.
2. `MonitoringBloc` memanggil `emit` dari callback stream setelah event handler selesai.
3. `StartMonitoring` dapat membuat subscription telemetry/koneksi ganda.
4. `MonitoringPage` membuat bloc lokal sementara `ControlPage` memakai bloc global.
5. Optimistic state tidak rollback saat timeout.
6. Sukses menulis Firebase dapat terlihat sebagai sukses perangkat sebelum ACK/status `/rooms` datang.
7. Satu command gagal mengganti seluruh monitoring menjadi `MonitoringError`.
8. Control screen menampilkan state kosong sebagai semua perangkat OFF.

### P1 — Data dan performa

1. Listener telemetry membaca root RTDB, bukan hanya `device/sensorData`.
2. Parsing power map malformed dapat memutus stream.
3. Brightness dipaksa `int`, sehingga nilai `num` lain dapat crash.
4. Query history mengabaikan parameter `limit`.
5. Batas tanggal memakai akhir hari `23:59:59` dan dapat kehilangan subdetik terakhir.
6. Request histori lama dapat menimpa request baru.
7. `sensorLogs` dan `energyData` mempunyai schema berbeda.

### P2 — UX dan maintainability

1. `.info/connected` harus diberi label koneksi Firebase, bukan kesehatan seluruh sistem.
2. Pending/failed/unknown perlu dibedakan dari ON/OFF.
3. Optimistic timer ada di BLoC dan widget sekaligus.
4. Provider `HistoryBloc` global tidak dipakai.
5. README masih template Flutter.
6. Dependency/helper/dead service dapat dibersihkan setelah test baseline tersedia.

### P3 — Release dan keamanan operasional

1. Android masih memakai application ID contoh dan debug signing untuk release.
2. Auth/role/App Check harus diputuskan berdasarkan model pengguna nyata sebelum rules diubah.
3. Gateway, peer ESP-NOW, dan telemetry belum mempunyai freshness/heartbeat contract lengkap.
4. Lisensi distribusi `syncfusion_flutter_gauges` harus diverifikasi pemilik proyek.

P3 memerlukan keputusan produk/deployment dan tidak boleh ditebak oleh perubahan kode otomatis.

## Desain Perbaikan

### Startup Firebase

Startup mempunyai dua hasil:

- sukses: buat `EshApp` dan seluruh Firebase service;
- gagal: tampilkan layar error startup dan tombol retry; jangan membangun bloc/service Firebase sebelum app tersedia.

Pesan pengguna dibuat singkat. Detail exception hanya dicetak melalui `debugPrint`.

### Satu MonitoringBloc

`MonitoringPage` dan `ControlPage` memakai instance `MonitoringBloc` yang sama dari root provider. `StartMonitoring` dibuat idempotent/restart-safe:

1. batalkan ketiga subscription lama;
2. buat subscription baru;
3. callback stream hanya menambahkan event BLoC;
4. `close()` membatalkan subscription dan timer.

### Desired, pending, confirmed

Sumber kebenaran aktuator adalah `/rooms`, karena master menulis path itu setelah relay lokal atau ACK slave diproses.

Flow command:

1. UI mengirim intent.
2. BLoC menyimpan optimistic value dan menandai `<room>/<device>` pending.
3. Firebase write sukses berarti command queued, bukan applied.
4. Update `/rooms` yang cocok dengan desired value menghapus pending.
5. Timeout/write failure menghapus pending dan rollback ke snapshot confirmed terbaru.
6. Failure command tidak menghapus telemetry sehat.

UI harus men-disable command perangkat selama key tersebut pending agar urutan command tidak ambigu.

### Stream telemetry

Listener dipersempit menjadi `device/sensorData`. Parser menerima `Map` saja; payload malformed menghasilkan data kosong/error terkontrol, bukan cast crash. Connection Firebase, gateway health, dan peer health tetap konsep terpisah.

### History

- Collection canonical: `sensorLogs`.
- Query memakai rentang half-open: `timestamp >= startDate` dan `timestamp < endDate`.
- Query wajib memakai `.limit(limit)`.
- Event limit diteruskan oleh BLoC.
- Rentang UI sehari berakhir pada awal hari berikutnya.
- Guard request terbaru mencegah hasil stale mengganti chart terbaru.

## Tahap Eksekusi

### Tahap A — Baseline

1. Jalankan `flutter analyze`.
2. Jalankan `flutter test`.
3. Catat failure awal.

### Tahap B — Startup dan lifecycle

1. Tambahkan startup error/retry.
2. Gunakan satu `MonitoringBloc`.
3. Jadikan start/retry restart-safe.
4. Ubah stream error menjadi event.
5. Test start berulang dan cleanup.

### Tahap C — Command confirmation

1. Simpan snapshot confirmed.
2. Cocokkan desired dengan update `/rooms`.
3. Rollback timeout/write failure.
4. Simpan error per device tanpa menjatuhkan seluruh monitoring.
5. Hapus timer pending widget; BLoC menjadi sumber tunggal.
6. Test queued, confirmed, timeout, dan write failure.

### Tahap D — Data/history

1. Persempit RTDB listener.
2. Amankan parser brightness/power/environment.
3. Terapkan history limit dan half-open range.
4. Tambahkan latest-request guard.
5. Test parser dan query contract.

### Tahap E — UI dan cleanup

1. Render loading/error/disconnected secara eksplisit di control.
2. Bedakan unknown dari OFF.
3. Tampilkan pending/failure per perangkat.
4. Hapus provider global/dead code yang terbukti tidak dipakai.
5. Ganti README template dengan dokumentasi proyek.

### Tahap F — Verifikasi

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Tidak menjalankan `flutter upgrade`, dependency major upgrade, Firebase deploy, firmware upload, atau release signing tanpa instruksi terpisah.

## Test Wajib

### MonitoringBloc

- start pertama membuat tiga stream;
- start ulang tidak meninggalkan subscription lama;
- callback error menghasilkan event/state aman;
- Firebase write success tetap pending sampai `/rooms` cocok;
- update `/rooms` cocok mengonfirmasi command;
- update lama tidak mengonfirmasi command baru;
- timeout rollback ke confirmed state;
- write failure mempertahankan telemetry;
- close membatalkan timer/subscription.

### FirebaseService

- telemetry map valid diparse;
- null/malformed tidak crash;
- brightness `int`/`double` dinormalisasi;
- history memakai collection `sensorLogs`;
- history memakai limit;
- rentang akhir bersifat eksklusif.

### UI

- monitoring loading/error/retry;
- control loading/error/disconnected;
- unknown tidak tampil sebagai OFF;
- pending men-disable control terkait;
- layout tetap terbaca pada lebar 320 px dan text scale 2x.

### Integrasi

1. App menulis command canonical.
2. Master membaca command.
3. Slave menerima command bila owner slave.
4. ACK kembali ke master.
5. Master menulis `/rooms`.
6. App mengubah pending menjadi confirmed.
7. Slave offline menghasilkan timeout, bukan status sukses.

## Definition of Done

- dokumentasi nomor 1 dan nomor 2 tersedia dan tidak lagi di-ignore;
- `firebase_options.dart` tidak berubah;
- `peerInfo.channel = 0` tidak berubah;
- satu MonitoringBloc melayani monitoring/control;
- stream tidak bocor saat retry/navigasi;
- command pending hanya selesai oleh confirmed state atau failure/timeout;
- history query dibatasi;
- analyzer dan test lulus;
- debug APK dapat dibangun;
- limitation hardware/Firebase deployment yang tidak dapat diuji lokal dicatat jelas.

## Pengembangan Berikutnya yang Memerlukan Keputusan

- application ID final dan release signing;
- Firebase Auth role (`viewer`/`controller`) dan App Check;
- heartbeat gateway/peer ESP-NOW;
- retention dan sampling history;
- migrasi/hapus `energyData`;
- independent brightness hardware untuk dua lampu kamar yang sekarang berbagi dimmer channel 1;
- distribusi Android dan kepatuhan lisensi Syncfusion.
