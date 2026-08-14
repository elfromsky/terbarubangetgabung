import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_slave_availability_use_case.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
import 'package:esh/screen/control.dart';
import 'package:esh/screen/monitoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeMonitoringRepository implements MonitoringRepository {
  final roomsController = StreamController<RoomDeviceCollection>.broadcast();
  bool? lastIsOn;
  int? lastBrightness;

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {
    lastIsOn = isOn;
    lastBrightness = brightness;
  }

  @override
  Stream<bool> getConnectionStatus() => Stream.value(true);

  @override
  Stream<bool?> getSlaveOnlineStream() => Stream.value(true);

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => const Stream.empty();

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() => roomsController.stream;

  Future<void> close() => roomsController.close();
}

const nowEpochSeconds = 2000000000;

class InertTimer implements Timer {
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() => _isActive = false;
}

MonitoringBloc createMonitoringBloc(FakeMonitoringRepository repository) {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(repository: repository),
    watchConnectionStatus: WatchConnectionStatusUseCase(repository: repository),
    watchRoomDevices: WatchRoomDevicesUseCase(repository: repository),
    watchSlaveAvailability: WatchSlaveAvailabilityUseCase(
      repository: repository,
    ),
    controlRoomDevice: ControlRoomDeviceUseCase(repository: repository),
    now: () => DateTime.fromMillisecondsSinceEpoch(nowEpochSeconds * 1000),
    pendingCommandTimeout: const Duration(milliseconds: 100),
    freshnessTimerFactory: (_, _) => InertTimer(),
  );
}

void enableControl(MonitoringBloc bloc) {
  bloc.add(
    DataUpdated(
      McbDataCollection(
        mcb1: McbDataCollection.empty().mcb1,
        heartbeatEpochSeconds: nowEpochSeconds,
      ),
    ),
  );
  bloc.add(ConnectionStatusChanged(true));
  bloc.add(SlaveAvailabilityChanged(true));
}

GoRouter createControlRouter(MonitoringBloc bloc) {
  return GoRouter(
    initialLocation: '/control',
    routes: [
      GoRoute(
        path: '/control',
        builder: (context, state) =>
            BlocProvider.value(value: bloc, child: const ControlPage()),
      ),
    ],
  );
}

GoRouter createMonitoringRouter(MonitoringBloc bloc) {
  return GoRouter(
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

RoomDeviceCollection terasDevices({bool includeValues = true}) {
  if (!includeValues) return RoomDeviceCollection.empty();
  return RoomDeviceCollection.empty()
      .set(
        const DeviceAddress(roomKey: 'teras', deviceKey: 'lampu'),
        const RoomDeviceValue(isOn: false),
      )
      .set(
        const DeviceAddress(roomKey: 'teras', deviceKey: 'sanyo'),
        const RoomDeviceValue(isOn: false),
      );
}

RoomDeviceCollection dapurLampu({required bool isOn, required int brightness}) {
  return RoomDeviceCollection.empty().set(
    const DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu'),
    RoomDeviceValue(isOn: isOn, brightness: brightness),
  );
}

RoomDeviceCollection controlDevices() {
  return terasDevices()
      .set(
        const DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu'),
        const RoomDeviceValue(isOn: true, brightness: 40),
      )
      .set(
        const DeviceAddress(roomKey: 'dapur', deviceKey: 'blower'),
        const RoomDeviceValue(isOn: false),
      );
}

Future<void> selectDapur(WidgetTester tester) async {
  await tester.tap(find.text('Teras').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dapur'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unknown status is not rendered as Mati', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeviceStatusCard(
            name: 'Lampu',
            supportsBrightness: true,
            viewState: DeviceControlViewState(
              phase: DeviceControlPhase.unknown,
              value: null,
              errorMessage: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Status belum tersedia'), findsOneWidget);
    expect(find.text('Mati'), findsNothing);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    final semantics = tester.getSemantics(find.byType(DeviceStatusCard));
    expect(semantics.label, contains('Lampu, Status belum tersedia'));
    expect(semantics.value, 'Status belum tersedia');
  });

  testWidgets('dimmable status displays preserved zero brightness', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeviceStatusCard(
            name: 'Lampu',
            supportsBrightness: true,
            viewState: DeviceControlViewState(
              phase: DeviceControlPhase.off,
              value: RoomDeviceValue(isOn: false, brightness: 0),
              errorMessage: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mati'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.byIcon(Icons.power_off), findsOneWidget);
  });

  testWidgets('failed status renders error text and error icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeviceStatusCard(
            name: 'Lampu',
            viewState: DeviceControlViewState(
              phase: DeviceControlPhase.failed,
              value: RoomDeviceValue(isOn: false),
              errorMessage: 'Perintah gagal dikirim',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Perintah gagal dikirim'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final semantics = tester.getSemantics(find.byType(DeviceStatusCard));
    expect(semantics.label, contains('Lampu, Perintah gagal dikirim'));
    expect(semantics.value, 'Perintah gagal dikirim');
  });

  testWidgets(
    'status card avoids horizontal overflow at 320px and 2x text scale',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: DeviceStatusCard(
                name: 'Perangkat dengan nama panjang',
                supportsBrightness: true,
                viewState: DeviceControlViewState(
                  phase: DeviceControlPhase.failed,
                  value: RoomDeviceValue(isOn: false, brightness: 0),
                  errorMessage: 'Perintah gagal dikirim',
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Perintah gagal dikirim'), findsOneWidget);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      });
    },
  );

  testWidgets(
    'ControlPage renders configured devices when typed state is empty',
    (tester) async {
      final repository = FakeMonitoringRepository();
      final bloc = createMonitoringBloc(repository);
      final router = createControlRouter(bloc);
      addTearDown(() async {
        router.dispose();
        await bloc.close();
        await repository.close();
      });

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      bloc.add(DeviceStateUpdated(RoomDeviceCollection.empty()));
      await tester.pump();

      expect(find.text('Status belum tersedia'), findsNWidgets(2));
      expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
      final buttons = tester
          .widgetList<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Nyalakan'),
          )
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons.every((button) => button.onPressed == null), isTrue);
    },
  );

  testWidgets('pending command disables only related control', (tester) async {
    final repository = FakeMonitoringRepository();
    final bloc = createMonitoringBloc(repository);
    final router = createControlRouter(bloc);
    addTearDown(() async {
      router.dispose();
      await bloc.close();
      await repository.close();
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    bloc.add(DeviceStateUpdated(terasDevices()));
    enableControl(bloc);
    await tester.pump();

    bloc.add(
      ControlRoomDevice(
        roomName: 'Teras',
        roomKey: 'teras',
        deviceName: 'Lampu',
        deviceKey: 'lampu',
        isOn: true,
        brightness: 100,
        supportsBrightness: false,
      ),
    );
    await tester.pump();

    final buttons = tester
        .widgetList<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Nyalakan'),
        )
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons[0].onPressed, isNull);
    expect(buttons[1].onPressed, isNotNull);
    bloc.add(
      DeviceStateUpdated(
        RoomDeviceCollection.empty()
            .set(
              const DeviceAddress(roomKey: 'teras', deviceKey: 'lampu'),
              const RoomDeviceValue(isOn: true),
            )
            .set(
              const DeviceAddress(roomKey: 'teras', deviceKey: 'sanyo'),
              const RoomDeviceValue(isOn: false),
            ),
      ),
    );
    await tester.pump();
  });

  testWidgets(
    'Slave offline disables Slave controls but leaves Teras enabled',
    (tester) async {
      final repository = FakeMonitoringRepository();
      final bloc = createMonitoringBloc(repository);
      final router = createControlRouter(bloc);
      addTearDown(() async {
        router.dispose();
        await bloc.close();
        await repository.close();
      });

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      bloc.add(DeviceStateUpdated(controlDevices()));
      enableControl(bloc);
      bloc.add(SlaveAvailabilityChanged(false));
      await tester.pump();

      expect(find.byKey(const Key('slave-unavailable-banner')), findsOneWidget);
      var terasButtons = tester
          .widgetList<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Nyalakan'),
          )
          .toList();
      expect(terasButtons, hasLength(2));
      expect(terasButtons.every((button) => button.onPressed != null), isTrue);

      await selectDapur(tester);

      final dimmerOn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Nyala'),
      );
      final blowerOn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Nyalakan'),
      );
      expect(dimmerOn.onPressed, isNull);
      expect(blowerOn.onPressed, isNull);
      expect(find.text('Status belum tersedia'), findsNWidgets(2));
      expect(find.text('40%'), findsNothing);
    },
  );

  testWidgets('failed known device keeps controls enabled', (tester) async {
    final repository = FakeMonitoringRepository();
    final bloc = createMonitoringBloc(repository);
    final router = createControlRouter(bloc);
    addTearDown(() async {
      router.dispose();
      await bloc.close();
      await repository.close();
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    bloc.add(DeviceStateUpdated(terasDevices()));
    enableControl(bloc);
    await tester.pump();
    bloc.add(
      CommandFailed(
        const DeviceAddress(roomKey: 'teras', deviceKey: 'lampu'),
        'Perintah gagal dikirim',
      ),
    );
    await tester.pump();

    expect(find.text('Perintah gagal dikirim'), findsNWidgets(2));
    final buttons = tester
        .widgetList<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Nyalakan'),
        )
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons.every((button) => button.onPressed != null), isTrue);
  });

  testWidgets('dimmer off keeps local brightness and sends it unchanged', (
    tester,
  ) async {
    final repository = FakeMonitoringRepository();
    final bloc = createMonitoringBloc(repository);
    final router = createControlRouter(bloc);
    addTearDown(() async {
      router.dispose();
      await bloc.close();
      await repository.close();
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    bloc.add(DeviceStateUpdated(dapurLampu(isOn: true, brightness: 35)));
    enableControl(bloc);
    await tester.pump();
    await selectDapur(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Mati'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 35);

    final sendButton = find.widgetWithText(ElevatedButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pump();
    expect(repository.lastIsOn, isFalse);
    expect(repository.lastBrightness, 35);
    bloc.add(DeviceStateUpdated(dapurLampu(isOn: false, brightness: 35)));
    await tester.pump();
  });

  testWidgets('dimmer on from zero uses minimum brightness one', (
    tester,
  ) async {
    final repository = FakeMonitoringRepository();
    final bloc = createMonitoringBloc(repository);
    final router = createControlRouter(bloc);
    addTearDown(() async {
      router.dispose();
      await bloc.close();
      await repository.close();
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    bloc.add(DeviceStateUpdated(dapurLampu(isOn: false, brightness: 0)));
    enableControl(bloc);
    await tester.pump();
    await selectDapur(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Nyala'));
    await tester.pump();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 1);
    expect(slider.value, 1);

    final sendButton = find.widgetWithText(ElevatedButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await tester.pump();
    expect(repository.lastIsOn, isTrue);
    expect(repository.lastBrightness, 1);
    bloc.add(DeviceStateUpdated(dapurLampu(isOn: true, brightness: 1)));
    await tester.pump();
  });

  testWidgets('monitoring masks stale power data with hash placeholders', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeMonitoringRepository();
    final bloc = createMonitoringBloc(repository);
    final router = createMonitoringRouter(bloc);
    addTearDown(() async {
      router.dispose();
      await bloc.close();
      await repository.close();
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    bloc.add(
      DataUpdated(
        const McbDataCollection(
          heartbeatEpochSeconds: nowEpochSeconds,
          mcb1: McbData(
            connected: true,
            voltage: 220,
            current: 1,
            power: 220,
            energy: 10,
            sampledAtEpochSeconds: nowEpochSeconds - 60,
          ),
          sensorData: SensorData(
            temperature: 28,
            humidity: 60,
            connected: true,
            sampledAtEpochSeconds: nowEpochSeconds - 60,
          ),
        ),
      ),
    );
    bloc.add(ConnectionStatusChanged(true));
    await tester.pump();

    expect(find.text('Status ESH'), findsOneWidget);
    expect(find.text('Koneksi Firebase'), findsOneWidget);
    expect(find.text('Sampel Kedaluwarsa'), findsOneWidget);
    expect(find.text('#'), findsNWidgets(6));
    expect(find.text('220.0'), findsNothing);
    expect(find.text('Rp 14407'), findsNothing);
  });

  testWidgets('monitoring status fits 320px at 2x text scale', (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repository = FakeMonitoringRepository();
    final bloc = createMonitoringBloc(repository);
    final router = createMonitoringRouter(bloc);
    addTearDown(() async {
      router.dispose();
      await bloc.close();
      await repository.close();
    });

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    enableControl(bloc);
    await tester.pump();
    bloc.add(ConnectionStatusChanged(false));
    await tester.pump();

    expect(find.text('Online (stale)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
