import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_slave_availability_use_case.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

/// Firebase Emulator-backed integration environment.
///
/// Every Firebase SDK used here is redirected to the local emulator suite via
/// [FirebaseAuth.useAuthEmulator] and [FirebaseDatabase.useDatabaseEmulator].
/// A **named** Firebase app (`esh-integration-test`) is used instead of the
/// default app so the `google-services.json`-registered production project is
/// never touched. The emulator host is resolved from the `ESH_EMULATOR_HOST`
/// dart-define:
///
/// - Android emulator: `10.0.2.2` (host loopback alias)
/// - host-side desktop/web: `127.0.0.1`
///
/// This suite MUST NOT run against a production Firebase project. The
/// [ensureEmulatorEnvironment] guard hard-fails unless the dedicated
/// `ESH_INTEGRATION=true` dart-define is present.

/// Synthetic, non-production project id used for every integration run.
const emulatorProjectId = 'esh-integration-test';

/// Fixed epoch-seconds base for deterministic freshness computation. All
/// seeded `unix_time`/`sampled_at` values are relative to this, and the bloc's
/// injected `now` clock is pinned to it so no wall-clock drift can flake the
/// 59s/60s boundary assertions.
const fixedNowEpochSeconds = 2000000000;

/// Auth emulator port (see `firebase/firebase.json`).
const authEmulatorPort = 9099;

/// Realtime Database emulator port (see `firebase/firebase.json`).
const databaseEmulatorPort = 9000;

/// Resolves the emulator host for the current test platform.
///
/// Android emulators reach the host loopback via `10.0.2.2`; everything else
/// (web, desktop, iOS simulator) uses `127.0.0.1`. Override with
/// `--dart-define=ESH_EMULATOR_HOST=...` when a different host is needed.
String get emulatorHost =>
    const String.fromEnvironment('ESH_EMULATOR_HOST', defaultValue: '10.0.2.2');

bool get _integrationFlagEnabled =>
    const bool.fromEnvironment('ESH_INTEGRATION', defaultValue: false);

DateTime get fixedNow =>
    DateTime.fromMillisecondsSinceEpoch(fixedNowEpochSeconds * 1000);

/// Hard-fail guard: refuse to run unless explicitly launched as an emulator
/// integration suite against the synthetic project id.
void ensureEmulatorEnvironment() {
  if (!_integrationFlagEnabled) {
    throw StateError(
      'Integration suite must be launched with '
      '--dart-define=ESH_INTEGRATION=true. Refusing to run against a '
      'potentially production Firebase project.',
    );
  }
}

FirebaseDatabase? _database;

/// The database instance bound to the emulator.
FirebaseDatabase get emulatorDatabase => _database!;

/// Initializes a named Firebase app, points it at the emulator suite, and signs
/// in as the provisioned `owner`/`controller` test principal.
///
/// The principal is pre-provisioned by `integration-tests/provision_owner.js`
/// (email/password user with `owner == true` and `controller == true` custom
/// claims). Signing in here yields the exact authorization the Flutter runtime
/// obtains in production from the anonymous + provisioned owner bootstrap, so
/// the real security rules are exercised, never bypassed.
Future<void> setUpEmulatorFirebase() async {
  ensureEmulatorEnvironment();

  final app = await Firebase.initializeApp(
    name: emulatorProjectId,
    options: FirebaseOptions(
      apiKey: 'emulator-only',
      appId: '1:000000000000:android:emulator-only',
      messagingSenderId: '000000000000',
      projectId: emulatorProjectId,
      databaseURL:
          'http://$emulatorHost:$databaseEmulatorPort/?ns=$emulatorProjectId',
    ),
  );

  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator(emulatorHost, authEmulatorPort);

  final database = FirebaseDatabase.instanceFor(
    app: app,
    databaseURL:
        'http://$emulatorHost:$databaseEmulatorPort/?ns=$emulatorProjectId',
  );
  database.useDatabaseEmulator(emulatorHost, databaseEmulatorPort);

  const email = String.fromEnvironment(
    'ESH_TEST_EMAIL',
    defaultValue: 'owner@esh.test',
  );
  const password = String.fromEnvironment(
    'ESH_TEST_PASSWORD',
    defaultValue: 'esh-test-password',
  );

  await auth.signInWithEmailAndPassword(email: email, password: password);

  // Force a token refresh so the owner/controller custom claims are present in
  // the ID token used by the Realtime Database SDK.
  final user = auth.currentUser!;
  await user.getIdTokenResult(true);

  _database = database;
}

/// A timer that never fires on its own, so the freshness expiry timer scheduled
/// by the bloc does not outlive the test or depend on the wall clock. The
/// automatic-expiry path is exercised explicitly by invoking the captured
/// callback.
class InertTimer implements Timer {
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

/// Builds a fully production-graph `MonitoringBloc` wired to the emulator RTDB,
/// with a pinned clock and inert freshness timers for determinism.
MonitoringBloc buildEmulatorMonitoringBloc({Stream<bool>? connectionStatus}) {
  final database = emulatorDatabase.ref();
  final monitoringDataSource = FirebaseMonitoringDataSource(database: database);
  final roomDeviceDataSource = FirebaseRoomDeviceDataSource(database: database);
  MonitoringRepository repository = MonitoringRepositoryImpl(
    monitoringDataSource: monitoringDataSource,
    roomDeviceDataSource: roomDeviceDataSource,
  );
  if (connectionStatus != null) {
    repository = _ConnectionStatusOverrideRepository(
      repository,
      connectionStatus,
    );
  }
  return buildMonitoringBlocForRepository(repository);
}

/// Wraps a repository so its connection-status stream can be driven directly.
///
/// This is used only for the *transport-disconnect* scenarios. The Firebase
/// realtime SDK's `goOffline`/`goOnline` do not deterministically re-emit
/// `.info/connected` on the emulator, so the connection status — and only the
/// connection status — is injected through this seam. Every other path
/// (telemetry reads, command writes, `/commands` read-back) still goes through
/// the real emulator-backed datasource. This is a *transport-loss simulation*,
/// not a physical network-outage test.
class _ConnectionStatusOverrideRepository implements MonitoringRepository {
  final MonitoringRepository _inner;
  final Stream<bool> _connectionStatus;

  _ConnectionStatusOverrideRepository(this._inner, this._connectionStatus);

  @override
  Stream<McbDataCollection> getMonitoringDataStream() =>
      _inner.getMonitoringDataStream();

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() =>
      _inner.getRoomDevicesStream();

  @override
  Stream<bool> getConnectionStatus() => _connectionStatus;

  @override
  Stream<bool?> getSlaveOnlineStream() => _inner.getSlaveOnlineStream();

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) => _inner.controlRoomDevice(
    roomKey,
    deviceKey,
    isOn,
    brightness,
    supportsBrightness,
  );
}

/// Builds a `MonitoringBloc` around an arbitrary repository.
MonitoringBloc buildMonitoringBlocForRepository(
  MonitoringRepository repository,
) {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(repository: repository),
    watchConnectionStatus: WatchConnectionStatusUseCase(repository: repository),
    watchRoomDevices: WatchRoomDevicesUseCase(repository: repository),
    watchSlaveAvailability: WatchSlaveAvailabilityUseCase(
      repository: repository,
    ),
    controlRoomDevice: ControlRoomDeviceUseCase(repository: repository),
    now: () => fixedNow,
    freshnessTimerFactory: (_, _) => InertTimer(),
    pendingCommandTimeout: const Duration(seconds: 5),
  );
}

/// Seeds `/device/sensorData` (heartbeat + power + environment) in the
/// emulator with the supplied epoch-second fields. A `null` field means the
/// key is omitted, matching the firmware's "write only when valid" behavior.
Future<void> seedSensorData({
  required int? unixTime,
  required Map<String, dynamic> power,
  required Map<String, dynamic> environment,
}) async {
  final data = <String, dynamic>{
    if (unixTime != null) 'unix_time': unixTime,
    'power': power,
    'environment': environment,
  };
  await emulatorDatabase.ref().child('device/sensorData').set(data);
}

/// Seeds `/rooms/<room>/tools/<device>` with an actual (reflected) state.
Future<void> seedRoomDevice({
  required String room,
  required String device,
  required bool isOn,
  int? brightness,
}) async {
  await emulatorDatabase.ref().child('rooms/$room/tools/$device').set({
    'state': isOn,
    if (brightness != null) 'brightness': brightness,
  });
}

/// Seeds `/gateway/status/slave/online` with the supplied value (`null` to
/// clear the key).
Future<void> seedSlaveOnline(bool? online) async {
  final ref = emulatorDatabase.ref().child('gateway/status/slave/online');
  if (online == null) {
    await ref.remove();
  } else {
    await ref.set(online);
  }
}

/// Reads whether a command currently exists at
/// `/commands/rooms/<room>/tools/<device>`. The test principal carries
/// `controller == true`, which the rules require for reading `/commands`.
Future<bool> commandExists({
  required String room,
  required String device,
}) async {
  final snapshot = await emulatorDatabase
      .ref('commands/rooms/$room/tools/$device')
      .get();
  return snapshot.exists;
}

/// Polls the bloc until [predicate] holds, failing after [timeout].
///
/// Realtime Database `onValue` delivery and bloc recomputation are
/// asynchronous; polling the bloc state is the simplest deterministic way to
/// await them without depending on frame scheduling.
Future<void> waitForBloc(
  MonitoringBloc bloc,
  bool Function(MonitoringBloc) predicate, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate(bloc)) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for bloc state: ${bloc.state}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
