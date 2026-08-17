import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/bloc/monitoring/monitoring_state.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:esh/screen/monitoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'emulator_env.dart';

/// Issue #24 — emulator-backed FR-18..FR-28 integration coverage.
///
/// These tests drive the *production* data path — real Realtime Database
/// emulator, real security rules, a provisioned owner/controller principal,
/// real `FirebaseMonitoringDataSource` -> mapper -> `MonitoringRepositoryImpl`
/// -> `MonitoringBloc` -> `MonitoringPage` — and assert the failure-safety
/// invariants:
///
///   1. heartbeat freshness is computed correctly (FR-18/FR-19);
///   2. unavailable data is visibly marked `#` (FR-22/FR-23/FR-24);
///   3. unsafe commands are suppressed at the RTDB level (FR-20/FR-28);
///   4. the last confirmed actual hardware state is preserved through
///      connection/heartbeat loss (FR-21).
///
/// Freshness is deterministic: the bloc's `now` clock is pinned to
/// `fixedNowEpochSeconds` and every seeded `unix_time`/`sampled_at` is relative
/// to it, so the exact 59s/60s boundary cannot drift.

// --- fixtures -------------------------------------------------------------

Map<String, dynamic> freshPower({int? sampledAt, bool connected = true}) => {
  'connected': connected,
  'voltage': 220,
  'current': 1,
  'power': 220,
  'energy': 10,
  'sampled_at': sampledAt ?? fixedNowEpochSeconds,
};

Map<String, dynamic> freshEnvironment({
  int? sampledAt,
  bool connected = true,
}) => {
  'connected': connected,
  'temperature': 28,
  'humidity': 60,
  'sampled_at': sampledAt ?? fixedNowEpochSeconds,
};

Map<String, dynamic> offlinePower() => {
  'connected': false,
  'voltage': 0,
  'current': 0,
  'power': 0,
  'energy': 0,
  'sampled_at': fixedNowEpochSeconds,
};

Map<String, dynamic> offlineEnvironment() => {
  'connected': false,
  'temperature': 0,
  'humidity': 0,
  'sampled_at': fixedNowEpochSeconds,
};

MonitoringLoaded loadedState(MonitoringBloc bloc) =>
    bloc.state as MonitoringLoaded;

bool isLoaded(MonitoringBloc bloc) => bloc.state is MonitoringLoaded;

Future<void> startMonitoring(MonitoringBloc bloc) async {
  bloc.add(StartMonitoring());
  await waitForBloc(bloc, isLoaded);
}

ControlRoomDevice controlEvent({
  required String roomKey,
  required String deviceKey,
  bool isOn = true,
  bool supportsBrightness = false,
}) {
  return ControlRoomDevice(
    roomName: roomKey,
    roomKey: roomKey,
    deviceName: deviceKey,
    deviceKey: deviceKey,
    isOn: isOn,
    brightness: isOn ? 100 : 0,
    supportsBrightness: supportsBrightness,
  );
}

Future<void> waitForCommand(String room, String device) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!(await commandExists(room: room, device: device))) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Command was not written to /commands/$room/$device',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

GoRouter monitoringRouter(MonitoringBloc bloc) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => BlocProvider.value(
          value: bloc,
          child: const MonitoringPage(
            estimateEnergyCost: EstimateEnergyCostUseCase(ratePerKwh: 1440.70),
            estimateEmission: EstimateEmissionUseCase(
              emissionFactorKgCo2PerKwh: 0.85,
            ),
          ),
        ),
      ),
    ],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setUpEmulatorFirebase();
  });

  group('heartbeat freshness truth table', () {
    Future<MonitoringLoaded> assertEshStatus({
      required int? unixTime,
      required EshSystemStatus expected,
    }) async {
      final bloc = buildEmulatorMonitoringBloc();
      addTearDown(bloc.close);
      await seedSensorData(
        unixTime: unixTime,
        power: freshPower(),
        environment: freshEnvironment(),
      );
      await seedSlaveOnline(true);
      await startMonitoring(bloc);
      await waitForBloc(
        bloc,
        (b) => isLoaded(b) && loadedState(b).eshStatus == expected,
      );
      final state = loadedState(bloc);
      expect(state.eshStatus, expected);
      expect(state.isConnected, isTrue);
      return state;
    }

    testWidgets('heartbeat age 0 seconds keeps ESH online', (tester) async {
      final state = await assertEshStatus(
        unixTime: fixedNowEpochSeconds,
        expected: EshSystemStatus.online,
      );
      expect(state.canControl, isTrue);
    });

    testWidgets('heartbeat age 59 seconds keeps ESH online', (tester) async {
      final state = await assertEshStatus(
        unixTime: fixedNowEpochSeconds - 59,
        expected: EshSystemStatus.online,
      );
      expect(state.canControl, isTrue);
    });

    testWidgets('heartbeat age exactly 60 seconds marks ESH offline', (
      tester,
    ) async {
      final state = await assertEshStatus(
        unixTime: fixedNowEpochSeconds - 60,
        expected: EshSystemStatus.offline,
      );
      expect(state.canControl, isFalse);
    });

    testWidgets('heartbeat age 61 seconds marks ESH offline', (tester) async {
      final state = await assertEshStatus(
        unixTime: fixedNowEpochSeconds - 61,
        expected: EshSystemStatus.offline,
      );
      expect(state.canControl, isFalse);
    });

    testWidgets('missing heartbeat keeps ESH status unknown', (tester) async {
      final state = await assertEshStatus(
        unixTime: null,
        expected: EshSystemStatus.unknown,
      );
      expect(state.canControl, isFalse);
    });

    testWidgets('future heartbeat keeps ESH status unknown', (tester) async {
      final state = await assertEshStatus(
        unixTime: fixedNowEpochSeconds + 1,
        expected: EshSystemStatus.unknown,
      );
      expect(state.canControl, isFalse);
    });
  });

  testWidgets(
    'global stale heartbeat overrides fresh power and environment modules',
    (tester) async {
      final bloc = buildEmulatorMonitoringBloc();
      addTearDown(bloc.close);
      await seedSensorData(
        unixTime: fixedNowEpochSeconds - 60,
        power: freshPower(),
        environment: freshEnvironment(),
      );
      await seedSlaveOnline(true);
      await startMonitoring(bloc);
      await waitForBloc(
        bloc,
        (b) =>
            isLoaded(b) && loadedState(b).eshStatus == EshSystemStatus.offline,
      );

      final state = loadedState(bloc);
      expect(state.isConnected, isTrue);
      expect(state.isPowerSampleFresh, isTrue);
      expect(state.isEnvironmentSampleFresh, isTrue);
      expect(state.mcbData.mcb1.connected, isTrue);
      expect(state.mcbData.sensorData.connected, isTrue);
      expect(state.canControl, isFalse);
      expect(state.canShowPowerData, isFalse);
      expect(state.canShowEnvironmentData, isFalse);
    },
  );

  testWidgets('power module explicit offline hides power data', (tester) async {
    final bloc = buildEmulatorMonitoringBloc();
    addTearDown(bloc.close);
    await seedSensorData(
      unixTime: fixedNowEpochSeconds,
      power: offlinePower(),
      environment: freshEnvironment(),
    );
    await seedSlaveOnline(true);
    await startMonitoring(bloc);
    await waitForBloc(
      bloc,
      (b) => isLoaded(b) && !loadedState(b).canShowPowerData,
    );

    final state = loadedState(bloc);
    expect(state.mcbData.mcb1.connected, isFalse);
    expect(state.canControl, isTrue);
    expect(state.canShowPowerData, isFalse);
    expect(state.canShowEnvironmentData, isTrue);
  });

  testWidgets('power sample stale hides power data', (tester) async {
    final bloc = buildEmulatorMonitoringBloc();
    addTearDown(bloc.close);
    await seedSensorData(
      unixTime: fixedNowEpochSeconds,
      power: freshPower(sampledAt: fixedNowEpochSeconds - 60),
      environment: freshEnvironment(),
    );
    await seedSlaveOnline(true);
    await startMonitoring(bloc);
    await waitForBloc(
      bloc,
      (b) => isLoaded(b) && !loadedState(b).canShowPowerData,
    );

    final state = loadedState(bloc);
    expect(state.isPowerSampleFresh, isFalse);
    expect(state.canShowPowerData, isFalse);
    expect(state.canShowEnvironmentData, isTrue);
  });

  testWidgets('environment module explicit offline hides environment data', (
    tester,
  ) async {
    final bloc = buildEmulatorMonitoringBloc();
    addTearDown(bloc.close);
    await seedSensorData(
      unixTime: fixedNowEpochSeconds,
      power: freshPower(),
      environment: offlineEnvironment(),
    );
    await seedSlaveOnline(true);
    await startMonitoring(bloc);
    await waitForBloc(
      bloc,
      (b) => isLoaded(b) && !loadedState(b).canShowEnvironmentData,
    );

    final state = loadedState(bloc);
    expect(state.mcbData.sensorData.connected, isFalse);
    expect(state.canShowPowerData, isTrue);
    expect(state.canShowEnvironmentData, isFalse);
  });

  testWidgets('environment sample stale hides environment data', (
    tester,
  ) async {
    final bloc = buildEmulatorMonitoringBloc();
    addTearDown(bloc.close);
    await seedSensorData(
      unixTime: fixedNowEpochSeconds,
      power: freshPower(),
      environment: freshEnvironment(sampledAt: fixedNowEpochSeconds - 60),
    );
    await seedSlaveOnline(true);
    await startMonitoring(bloc);
    await waitForBloc(
      bloc,
      (b) => isLoaded(b) && !loadedState(b).canShowEnvironmentData,
    );

    final state = loadedState(bloc);
    expect(state.isEnvironmentSampleFresh, isFalse);
    expect(state.canShowEnvironmentData, isFalse);
    expect(state.canShowPowerData, isTrue);
  });

  testWidgets('missing Firebase fields are mapped to unavailable modules', (
    tester,
  ) async {
    final bloc = buildEmulatorMonitoringBloc();
    addTearDown(bloc.close);
    await seedSensorData(
      unixTime: fixedNowEpochSeconds,
      power: const {},
      environment: const {},
    );
    await seedSlaveOnline(true);
    await startMonitoring(bloc);
    await waitForBloc(
      bloc,
      (b) =>
          isLoaded(b) &&
          !loadedState(b).canShowPowerData &&
          !loadedState(b).canShowEnvironmentData,
    );

    final state = loadedState(bloc);
    expect(state.mcbData.mcb1.connected, isFalse);
    expect(state.mcbData.sensorData.connected, isFalse);
    expect(state.canControl, isTrue);
  });

  group('Firebase connection vs ESH system status', () {
    testWidgets(
      'Firebase disconnect retains ESH status as stale and blocks control',
      (tester) async {
        final connectionController = StreamController<bool>.broadcast();
        addTearDown(connectionController.close);
        final bloc = buildEmulatorMonitoringBloc(
          connectionStatus: connectionController.stream,
        );
        addTearDown(bloc.close);
        await seedSensorData(
          unixTime: fixedNowEpochSeconds,
          power: freshPower(),
          environment: freshEnvironment(),
        );
        await seedSlaveOnline(true);
        await startMonitoring(bloc);
        connectionController.add(true);
        await waitForBloc(
          bloc,
          (b) =>
              isLoaded(b) &&
              loadedState(b).eshStatus == EshSystemStatus.online &&
              loadedState(b).isConnected,
        );

        // Transport loss (simulated seam) — connection drops, ESH status is
        // retained as stale, control is blocked.
        connectionController.add(false);
        await waitForBloc(
          bloc,
          (b) => isLoaded(b) && !loadedState(b).isConnected,
        );

        final offline = loadedState(bloc);
        expect(offline.eshStatus, EshSystemStatus.online);
        expect(offline.isEshStatusStale, isTrue);
        expect(offline.canControl, isFalse);
      },
    );

    testWidgets(
      'control intent while Firebase disconnected does not write command',
      (tester) async {
        final connectionController = StreamController<bool>.broadcast();
        addTearDown(connectionController.close);
        final bloc = buildEmulatorMonitoringBloc(
          connectionStatus: connectionController.stream,
        );
        addTearDown(bloc.close);
        await seedSensorData(
          unixTime: fixedNowEpochSeconds,
          power: freshPower(),
          environment: freshEnvironment(),
        );
        await seedRoomDevice(room: 'teras', device: 'sanyo', isOn: false);
        await seedSlaveOnline(true);
        await startMonitoring(bloc);
        connectionController.add(true);
        await waitForBloc(
          bloc,
          (b) => isLoaded(b) && loadedState(b).isConnected,
        );

        connectionController.add(false);
        await waitForBloc(
          bloc,
          (b) => isLoaded(b) && !loadedState(b).isConnected,
        );

        bloc.add(controlEvent(roomKey: 'teras', deviceKey: 'sanyo'));
        await waitForBloc(
          bloc,
          (b) => isLoaded(b) && loadedState(b).commandErrors.isNotEmpty,
        );

        expect(
          loadedState(bloc).controlDisabledReason,
          'Firebase terputus. Perintah tidak dikirim',
        );
        expect(loadedState(bloc).pendingDevices, isEmpty);
        expect(await commandExists(room: 'teras', device: 'sanyo'), isFalse);
      },
    );
  });

  group('command suppression', () {
    testWidgets('command is emitted when Firebase and ESH are online', (
      tester,
    ) async {
      final bloc = buildEmulatorMonitoringBloc();
      addTearDown(bloc.close);
      await seedSensorData(
        unixTime: fixedNowEpochSeconds,
        power: freshPower(),
        environment: freshEnvironment(),
      );
      await seedRoomDevice(room: 'teras', device: 'lampu', isOn: false);
      await seedSlaveOnline(true);
      await startMonitoring(bloc);
      await waitForBloc(bloc, (b) => isLoaded(b) && loadedState(b).canControl);

      bloc.add(controlEvent(roomKey: 'teras', deviceKey: 'lampu'));
      await waitForCommand('teras', 'lampu');
    });

    testWidgets('control intent while heartbeat stale does not write command', (
      tester,
    ) async {
      final bloc = buildEmulatorMonitoringBloc();
      addTearDown(bloc.close);
      await seedSensorData(
        unixTime: fixedNowEpochSeconds - 60,
        power: freshPower(),
        environment: freshEnvironment(),
      );
      await seedRoomDevice(room: 'lorong', device: 'blower', isOn: false);
      await seedSlaveOnline(true);
      await startMonitoring(bloc);
      await waitForBloc(
        bloc,
        (b) =>
            isLoaded(b) && loadedState(b).eshStatus == EshSystemStatus.offline,
      );

      bloc.add(controlEvent(roomKey: 'lorong', deviceKey: 'blower'));
      await waitForBloc(
        bloc,
        (b) => isLoaded(b) && loadedState(b).commandErrors.isNotEmpty,
      );

      expect(
        loadedState(bloc).controlDisabledReason,
        'Sistem ESH offline. Perintah tidak dikirim',
      );
      expect(loadedState(bloc).pendingDevices, isEmpty);
      expect(await commandExists(room: 'lorong', device: 'blower'), isFalse);
    });

    testWidgets(
      'control intent while ESH status unknown does not write command',
      (tester) async {
        final bloc = buildEmulatorMonitoringBloc();
        addTearDown(bloc.close);
        await seedSensorData(
          unixTime: null,
          power: freshPower(),
          environment: freshEnvironment(),
        );
        await seedRoomDevice(
          room: 'lorong',
          device: 'stop_kontak',
          isOn: false,
        );
        await seedSlaveOnline(true);
        await startMonitoring(bloc);
        await waitForBloc(
          bloc,
          (b) =>
              isLoaded(b) &&
              loadedState(b).eshStatus == EshSystemStatus.unknown,
        );

        bloc.add(controlEvent(roomKey: 'lorong', deviceKey: 'stop_kontak'));
        await waitForBloc(
          bloc,
          (b) => isLoaded(b) && loadedState(b).commandErrors.isNotEmpty,
        );

        expect(
          loadedState(bloc).controlDisabledReason,
          'Status ESH belum tersedia. Perintah tidak dikirim',
        );
        expect(
          await commandExists(room: 'lorong', device: 'stop_kontak'),
          isFalse,
        );
      },
    );
  });

  group('Slave availability and ownership', () {
    testWidgets('Slave offline blocks command to Slave-owned device', (
      tester,
    ) async {
      final bloc = buildEmulatorMonitoringBloc();
      addTearDown(bloc.close);
      await seedSensorData(
        unixTime: fixedNowEpochSeconds,
        power: freshPower(),
        environment: freshEnvironment(),
      );
      await seedRoomDevice(room: 'dapur', device: 'blower', isOn: false);
      await seedSlaveOnline(false);
      await startMonitoring(bloc);
      await waitForBloc(
        bloc,
        (b) => isLoaded(b) && loadedState(b).slaveOnline == false,
      );

      final address = const DeviceAddress(
        roomKey: 'dapur',
        deviceKey: 'blower',
      );
      expect(loadedState(bloc).canControl, isTrue);
      expect(loadedState(bloc).canControlDevice(address), isFalse);

      bloc.add(controlEvent(roomKey: 'dapur', deviceKey: 'blower'));
      await waitForBloc(
        bloc,
        (b) => isLoaded(b) && loadedState(b).commandErrors.isNotEmpty,
      );

      expect(
        loadedState(bloc).controlDisabledReasonFor(address),
        'Slave tidak tersedia. Perintah tidak dikirim',
      );
      expect(await commandExists(room: 'dapur', device: 'blower'), isFalse);
    });

    testWidgets('Master-owned device is not disabled solely by Slave offline', (
      tester,
    ) async {
      final bloc = buildEmulatorMonitoringBloc();
      addTearDown(bloc.close);
      await seedSensorData(
        unixTime: fixedNowEpochSeconds,
        power: freshPower(),
        environment: freshEnvironment(),
      );
      await seedRoomDevice(room: 'teras', device: 'lampu', isOn: false);
      await seedSlaveOnline(false);
      await startMonitoring(bloc);
      await waitForBloc(
        bloc,
        (b) => isLoaded(b) && loadedState(b).slaveOnline == false,
      );

      const address = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
      expect(loadedState(bloc).canControlDevice(address), isTrue);

      bloc.add(controlEvent(roomKey: 'teras', deviceKey: 'lampu'));
      await waitForCommand('teras', 'lampu');
    });
  });

  group('last confirmed hardware state retention', () {
    testWidgets(
      'last confirmed device state is retained through connection loss',
      (tester) async {
        final connectionController = StreamController<bool>.broadcast();
        addTearDown(connectionController.close);
        final bloc = buildEmulatorMonitoringBloc(
          connectionStatus: connectionController.stream,
        );
        addTearDown(bloc.close);
        await seedSensorData(
          unixTime: fixedNowEpochSeconds,
          power: freshPower(),
          environment: freshEnvironment(),
        );
        await seedRoomDevice(room: 'teras', device: 'lampu', isOn: true);
        await seedSlaveOnline(true);
        await startMonitoring(bloc);
        connectionController.add(true);
        await waitForBloc(
          bloc,
          (b) =>
              isLoaded(b) &&
              loadedState(b).deviceData
                      .find(
                        const DeviceAddress(
                          roomKey: 'teras',
                          deviceKey: 'lampu',
                        ),
                      )
                      ?.isOn ==
                  true,
        );

        connectionController.add(false);
        await waitForBloc(
          bloc,
          (b) => isLoaded(b) && !loadedState(b).isConnected,
        );

        final state = loadedState(bloc);
        final lampu = state.deviceData.find(
          const DeviceAddress(roomKey: 'teras', deviceKey: 'lampu'),
        );
        expect(lampu?.isOn, isTrue);
        expect(state.desiredDevices, isEmpty);
        expect(state.pendingDevices, isEmpty);
      },
    );

    testWidgets(
      'last confirmed device state is retained through heartbeat expiry',
      (tester) async {
        final bloc = buildEmulatorMonitoringBloc();
        addTearDown(bloc.close);
        await seedSensorData(
          unixTime: fixedNowEpochSeconds,
          power: freshPower(),
          environment: freshEnvironment(),
        );
        await seedRoomDevice(
          room: 'dapur',
          device: 'lampu',
          isOn: true,
          brightness: 60,
        );
        await seedSlaveOnline(true);
        await startMonitoring(bloc);
        await waitForBloc(
          bloc,
          (b) =>
              isLoaded(b) &&
              loadedState(b).deviceData
                      .find(
                        const DeviceAddress(
                          roomKey: 'dapur',
                          deviceKey: 'lampu',
                        ),
                      )
                      ?.isOn ==
                  true,
        );

        // Heartbeat ages past the 60s boundary: re-seed a stale heartbeat while
        // the reflected room state is unchanged.
        await seedSensorData(
          unixTime: fixedNowEpochSeconds - 60,
          power: freshPower(),
          environment: freshEnvironment(),
        );
        await waitForBloc(
          bloc,
          (b) =>
              isLoaded(b) &&
              loadedState(b).eshStatus == EshSystemStatus.offline,
        );

        final state = loadedState(bloc);
        final lampu = state.deviceData.find(
          const DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu'),
        );
        expect(lampu?.isOn, isTrue);
        expect(lampu?.brightness, 60);
        expect(state.desiredDevices, isEmpty);
      },
    );
  });

  group('offline hash rendering', () {
    testWidgets(
      'stale heartbeat hides power data and derived cost/emission as hash',
      (tester) async {
        final bloc = buildEmulatorMonitoringBloc();
        addTearDown(bloc.close);
        await seedSensorData(
          unixTime: fixedNowEpochSeconds - 60,
          power: freshPower(),
          environment: freshEnvironment(),
        );
        await seedSlaveOnline(true);
        await startMonitoring(bloc);
        await waitForBloc(
          bloc,
          (b) =>
              isLoaded(b) &&
              loadedState(b).eshStatus == EshSystemStatus.offline,
        );

        final router = monitoringRouter(bloc);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump();

        expect(find.text('Status ESH'), findsOneWidget);
        expect(find.text('Offline'), findsOneWidget);
        expect(find.text('Koneksi Firebase'), findsOneWidget);
        expect(find.text('Terhubung'), findsOneWidget);
        expect(find.text('#'), findsNWidgets(6));
        expect(find.text('220.0'), findsNothing);
        expect(find.textContaining('Rp '), findsNothing);
      },
    );

    testWidgets(
      'environment module offline hides heat index and categories as hash',
      (tester) async {
        final bloc = buildEmulatorMonitoringBloc();
        addTearDown(bloc.close);
        await seedSensorData(
          unixTime: fixedNowEpochSeconds,
          power: freshPower(),
          environment: offlineEnvironment(),
        );
        await seedSlaveOnline(true);
        await startMonitoring(bloc);
        await waitForBloc(
          bloc,
          (b) => isLoaded(b) && !loadedState(b).canShowEnvironmentData,
        );

        final router = monitoringRouter(bloc);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump();

        await tester.tap(find.text('Listrik'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Suhu & Kelembapan'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Module Offline'), findsOneWidget);
        expect(find.text('#'), findsNWidgets(5));
        expect(find.textContaining('°C'), findsNothing);
      },
    );
  });
}
