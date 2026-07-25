import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
import 'package:esh/screen/control.dart';
import 'package:esh/screen/monitoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeMonitoringRepository implements MonitoringRepository {
  final roomsController = StreamController<RoomDeviceCollection>.broadcast();

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {}

  @override
  Stream<bool> getConnectionStatus() => const Stream.empty();

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => const Stream.empty();

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() => roomsController.stream;

  Future<void> close() => roomsController.close();
}

MonitoringBloc createMonitoringBloc(FakeMonitoringRepository repository) {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(repository: repository),
    watchConnectionStatus: WatchConnectionStatusUseCase(repository: repository),
    watchRoomDevices: WatchRoomDevicesUseCase(repository: repository),
    controlRoomDevice: ControlRoomDeviceUseCase(repository: repository),
  );
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
}
