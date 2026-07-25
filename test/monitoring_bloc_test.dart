import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/bloc/monitoring/monitoring_state.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonitoringRepository implements MonitoringRepository {
  final monitoringController = StreamController<McbDataCollection>.broadcast();
  final roomsController = StreamController<RoomDeviceCollection>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  int monitoringListeners = 0;
  bool failControl = false;
  int? lastBrightness;
  bool? lastIsOn;
  String? lastRoomKey;
  String? lastDeviceKey;

  late final Stream<McbDataCollection> monitoringStream = Stream.multi((sink) {
    monitoringListeners++;
    final subscription = monitoringController.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => monitoringStream;

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() => roomsController.stream;

  @override
  Stream<bool> getConnectionStatus() => connectionController.stream;

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {
    lastRoomKey = roomKey;
    lastDeviceKey = deviceKey;
    lastIsOn = isOn;
    lastBrightness = brightness;
    if (failControl) throw Exception('write failed');
  }

  Future<void> close() async {
    await monitoringController.close();
    await roomsController.close();
    await connectionController.close();
  }
}

const terasLampu = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
const terasSanyo = DeviceAddress(roomKey: 'teras', deviceKey: 'sanyo');

RoomDeviceCollection roomState({required bool lampu, bool? sanyo}) {
  var collection = RoomDeviceCollection.empty().set(
    terasLampu,
    RoomDeviceValue(isOn: lampu),
  );
  if (sanyo != null) {
    collection = collection.set(terasSanyo, RoomDeviceValue(isOn: sanyo));
  }
  return collection;
}

MonitoringBloc createMonitoringBloc(FakeMonitoringRepository repository) {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(repository: repository),
    watchConnectionStatus: WatchConnectionStatusUseCase(repository: repository),
    watchRoomDevices: WatchRoomDevicesUseCase(repository: repository),
    controlRoomDevice: ControlRoomDeviceUseCase(repository: repository),
  );
}

Future<void> waitForState(
  MonitoringBloc bloc,
  bool Function(MonitoringState state) predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (predicate(bloc.state)) return;
  await bloc.stream.firstWhere(predicate).timeout(timeout);
}

void main() {
  late FakeMonitoringRepository repository;
  late MonitoringBloc bloc;

  setUp(() {
    repository = FakeMonitoringRepository();
    bloc = createMonitoringBloc(repository);
  });

  tearDown(() async {
    await bloc.close();
    await repository.close();
  });

  test('StartMonitoring is idempotent while monitoring is active', () async {
    bloc.add(StartMonitoring());
    await waitForState(bloc, (state) => state is MonitoringLoading);
    await Future<void>.delayed(Duration.zero);

    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.monitoringListeners, 1);
  });

  test('matching room update confirms pending command', () async {
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(roomState(lampu: false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.confirmedDeviceData.values.isNotEmpty,
    );

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
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.pendingDevices.contains(terasLampu),
    );

    repository.roomsController.add(roomState(lampu: true));
    await waitForState(
      bloc,
      (state) => state is MonitoringLoaded && state.pendingDevices.isEmpty,
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.commandErrors, isEmpty);
    expect(state.deviceData.find(terasLampu)?.isOn, isTrue);
  });

  test(
    'optimistic brightness and command payload use int clamp normalization',
    () async {
      bloc.add(StartMonitoring());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repository.roomsController.add(
        RoomDeviceCollection.empty().set(
          terasLampu,
          const RoomDeviceValue(isOn: false, brightness: 20),
        ),
      );
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.confirmedDeviceData.values.isNotEmpty,
      );

      bloc.add(
        ControlRoomDevice(
          roomName: 'Teras',
          roomKey: 'teras',
          deviceName: 'Lampu',
          deviceKey: 'lampu',
          isOn: true,
          brightness: 150.9,
          supportsBrightness: true,
        ),
      );
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.pendingDevices.contains(terasLampu),
      );

      final state = bloc.state as MonitoringLoaded;
      expect(
        state.deviceData.find(terasLampu),
        const RoomDeviceValue(isOn: true, brightness: 100),
      );
      expect(repository.lastBrightness, 100);
      expect(repository.lastIsOn, isTrue);
      expect(repository.lastRoomKey, 'teras');
      expect(repository.lastDeviceKey, 'lampu');
    },
  );

  test(
    'unrelated confirmed update does not erase another pending command',
    () async {
      bloc.add(StartMonitoring());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repository.roomsController.add(roomState(lampu: false, sanyo: false));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.confirmedDeviceData.values.length == 2,
      );

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
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.pendingDevices.contains(terasLampu),
      );

      bloc.add(
        ControlRoomDevice(
          roomName: 'Teras',
          roomKey: 'teras',
          deviceName: 'Sanyo',
          deviceKey: 'sanyo',
          isOn: true,
          brightness: 100,
          supportsBrightness: false,
        ),
      );
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.pendingDevices.contains(terasLampu) &&
            state.pendingDevices.contains(terasSanyo),
      );

      repository.roomsController.add(roomState(lampu: false, sanyo: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = bloc.state as MonitoringLoaded;
      expect(state.pendingDevices, contains(terasLampu));
      expect(state.pendingDevices, isNot(contains(terasSanyo)));
      expect(state.deviceData.find(terasLampu)?.isOn, isTrue);
      expect(state.deviceData.find(terasSanyo)?.isOn, isTrue);
      expect(state.confirmedDeviceData.find(terasSanyo)?.isOn, isTrue);
    },
  );

  test('write failure rolls back to confirmed room state', () async {
    repository.failControl = true;
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(roomState(lampu: false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.confirmedDeviceData.values.isNotEmpty,
    );

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
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.commandErrors.containsKey(terasLampu),
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.pendingDevices, isEmpty);
    expect(state.deviceData.find(terasLampu)?.isOn, isFalse);
    expect(state.confirmedDeviceData.find(terasLampu)?.isOn, isFalse);
    expect(state.commandErrors[terasLampu], 'Perintah gagal dikirim');
  });

  test(
    'timeout rolls back to latest confirmed value and records timeout error',
    () async {
      bloc.add(StartMonitoring());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repository.roomsController.add(roomState(lampu: false));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.confirmedDeviceData.find(terasLampu) != null,
      );

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
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.pendingDevices.contains(terasLampu),
      );

      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.commandErrors.containsKey(terasLampu),
        timeout: const Duration(seconds: 7),
      );

      final state = bloc.state as MonitoringLoaded;
      expect(state.pendingDevices, isEmpty);
      expect(state.deviceData.find(terasLampu)?.isOn, isFalse);
      expect(state.confirmedDeviceData.find(terasLampu)?.isOn, isFalse);
      expect(
        state.commandErrors[terasLampu],
        'Perintah tidak dikonfirmasi perangkat',
      );
    },
  );
}
