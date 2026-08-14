import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/bloc/monitoring/monitoring_state.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/history/domain/usecases/save_sensor_log_use_case.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_slave_availability_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

const nowEpochSeconds = 2000000000;

DateTime get fixedNow =>
    DateTime.fromMillisecondsSinceEpoch(nowEpochSeconds * 1000);

McbDataCollection monitoringDataWithHeartbeat(int? heartbeatEpochSeconds) {
  return McbDataCollection(
    mcb1: McbDataCollection.empty().mcb1,
    heartbeatEpochSeconds: heartbeatEpochSeconds,
  );
}

class FakeHistoryRepositoryForBloc implements HistoryRepository {
  McbDataCollection? savedCollection;

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async => const [];

  @override
  Future<void> saveSensorLog(McbDataCollection collection) async {
    savedCollection = collection;
  }
}

class FakeMonitoringRepository implements MonitoringRepository {
  final monitoringController = StreamController<McbDataCollection>.broadcast();
  final roomsController = StreamController<RoomDeviceCollection>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  int monitoringListeners = 0;
  bool failControl = false;
  Completer<void>? controlCompleter;
  int? lastBrightness;
  bool? lastIsOn;
  String? lastRoomKey;
  String? lastDeviceKey;
  int controlCallCount = 0;
  Future<void> Function(int call)? controlHandler;

  late final Stream<McbDataCollection> monitoringStream = Stream.multi((sink) {
    monitoringListeners++;
    sink.add(monitoringDataWithHeartbeat(nowEpochSeconds));
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
  Stream<bool> getConnectionStatus() => Stream.value(true);

  @override
  Stream<bool?> getSlaveOnlineStream() => Stream.value(true);

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
    controlCallCount++;
    if (controlHandler != null) await controlHandler!(controlCallCount);
    if (failControl) throw Exception('write failed');
    await controlCompleter?.future;
  }

  Future<void> close() async {
    await monitoringController.close();
    await roomsController.close();
    await connectionController.close();
  }
}

const terasLampu = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');
const terasSanyo = DeviceAddress(roomKey: 'teras', deviceKey: 'sanyo');
const kamar1Lampu = DeviceAddress(roomKey: 'kamar_1', deviceKey: 'lampu');
const kamar2Lampu = DeviceAddress(roomKey: 'kamar_2', deviceKey: 'lampu');
const dapurBlower = DeviceAddress(roomKey: 'dapur', deviceKey: 'blower');

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

MonitoringBloc createMonitoringBloc(
  FakeMonitoringRepository repository, {
  DateTime Function()? now,
  Duration pendingCommandTimeout = const Duration(milliseconds: 80),
  Timer Function(Duration, void Function())? freshnessTimerFactory,
  SaveSensorLogUseCase? saveSensorLog,
}) {
  return MonitoringBloc(
    watchMonitoringData: WatchMonitoringDataUseCase(repository: repository),
    watchConnectionStatus: WatchConnectionStatusUseCase(repository: repository),
    watchRoomDevices: WatchRoomDevicesUseCase(repository: repository),
    watchSlaveAvailability: WatchSlaveAvailabilityUseCase(
      repository: repository,
    ),
    controlRoomDevice: ControlRoomDeviceUseCase(repository: repository),
    saveSensorLog: saveSensorLog,
    now: now ?? () => fixedNow,
    pendingCommandTimeout: pendingCommandTimeout,
    freshnessTimerFactory: freshnessTimerFactory,
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

Future<void> setConnectedHeartbeat(
  MonitoringBloc bloc,
  int? heartbeatEpochSeconds,
) async {
  bloc.add(DataUpdated(monitoringDataWithHeartbeat(heartbeatEpochSeconds)));
  await waitForState(
    bloc,
    (state) =>
        state is MonitoringLoaded &&
        state.mcbData.heartbeatEpochSeconds == heartbeatEpochSeconds,
  );
  bloc.add(ConnectionStatusChanged(true));
}

ControlRoomDevice turnOnTerasLampu() {
  return ControlRoomDevice(
    roomName: 'Teras',
    roomKey: 'teras',
    deviceName: 'Lampu',
    deviceKey: 'lampu',
    isOn: true,
    brightness: 100,
    supportsBrightness: false,
  );
}

ControlRoomDevice turnOnDapurBlower() {
  return ControlRoomDevice(
    roomName: 'Dapur',
    roomKey: 'dapur',
    deviceName: 'Blower',
    deviceKey: 'blower',
    isOn: true,
    brightness: 100,
    supportsBrightness: false,
  );
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
    bloc.add(StartMonitoring());
    await waitForState(bloc, (state) => state is MonitoringLoading);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.monitoringListeners, 1);
  });

  test('pending command timeout defaults to firmware retry window', () {
    expect(
      MonitoringBloc.defaultPendingCommandTimeout,
      const Duration(seconds: 12),
    );
  });

  test('missing heartbeat keeps ESH status unknown', () async {
    await setConnectedHeartbeat(bloc, null);
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.isConnected &&
          state.eshStatus == EshSystemStatus.unknown,
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.canControl, isFalse);
  });

  test('future heartbeat keeps ESH status unknown', () async {
    await setConnectedHeartbeat(bloc, nowEpochSeconds + 1);
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.eshStatus == EshSystemStatus.unknown,
    );

    expect((bloc.state as MonitoringLoaded).canControl, isFalse);
  });

  test('heartbeat age 59 seconds is online', () async {
    await setConnectedHeartbeat(bloc, nowEpochSeconds - 59);
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.eshStatus == EshSystemStatus.online,
    );

    expect((bloc.state as MonitoringLoaded).canControl, isTrue);
  });

  test('heartbeat age exactly 60 seconds is offline', () async {
    await setConnectedHeartbeat(bloc, nowEpochSeconds - 60);
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.eshStatus == EshSystemStatus.offline,
    );

    expect((bloc.state as MonitoringLoaded).canControl, isFalse);
  });

  test(
    'module samples display only from age zero through 59 seconds',
    () async {
      McbDataCollection dataAt(int sampledAt) => McbDataCollection(
        heartbeatEpochSeconds: nowEpochSeconds,
        mcb1: McbData(
          connected: true,
          voltage: 220,
          current: 1,
          power: 220,
          energy: 1,
          sampledAtEpochSeconds: sampledAt,
        ),
        sensorData: SensorData(
          temperature: 28,
          humidity: 60,
          connected: true,
          sampledAtEpochSeconds: sampledAt,
        ),
      );

      bloc.add(DataUpdated(dataAt(nowEpochSeconds - 59)));
      bloc.add(ConnectionStatusChanged(true));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.canShowPowerData &&
            state.canShowEnvironmentData,
      );

      bloc.add(DataUpdated(dataAt(nowEpochSeconds - 60)));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            !state.canShowPowerData &&
            !state.canShowEnvironmentData,
      );

      bloc.add(DataUpdated(dataAt(nowEpochSeconds + 1)));
      await Future<void>.delayed(Duration.zero);
      final state = bloc.state as MonitoringLoaded;
      expect(state.canShowPowerData, isFalse);
      expect(state.canShowEnvironmentData, isFalse);
    },
  );

  test('online heartbeat expires without new telemetry', () async {
    var now = fixedNow;
    Duration? scheduledDelay;
    void Function()? expiryCallback;
    await bloc.close();
    bloc = createMonitoringBloc(
      repository,
      now: () => now,
      freshnessTimerFactory: (delay, callback) {
        scheduledDelay = delay;
        expiryCallback = callback;
        return Timer(const Duration(days: 1), () {});
      },
    );

    await setConnectedHeartbeat(bloc, nowEpochSeconds - 59);
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.eshStatus == EshSystemStatus.online,
    );
    expect(scheduledDelay, const Duration(seconds: 1));

    now = now.add(const Duration(seconds: 1));
    expiryCallback!();
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.eshStatus == EshSystemStatus.offline,
    );

    expect((bloc.state as MonitoringLoaded).canControl, isFalse);
  });

  test(
    'Firebase disconnect retains ESH status as stale and reconnects',
    () async {
      var now = fixedNow;
      await bloc.close();
      bloc = createMonitoringBloc(repository, now: () => now);
      await setConnectedHeartbeat(bloc, nowEpochSeconds - 59);
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.eshStatus == EshSystemStatus.online,
      );

      bloc.add(ConnectionStatusChanged(false));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            !state.isConnected &&
            state.isEshStatusStale,
      );
      var state = bloc.state as MonitoringLoaded;
      expect(state.eshStatus, EshSystemStatus.online);
      expect(state.canControl, isFalse);

      now = now.add(const Duration(seconds: 2));
      bloc.add(ConnectionStatusChanged(true));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.isConnected &&
            state.eshStatus == EshSystemStatus.offline,
      );
      state = bloc.state as MonitoringLoaded;
      expect(state.isEshStatusStale, isFalse);
      expect(state.canControl, isFalse);
    },
  );

  test(
    'command is rejected when Firebase connects without heartbeat',
    () async {
      bloc.add(DeviceStateUpdated(roomState(lampu: false)));
      await waitForState(bloc, (state) => state is MonitoringLoaded);
      await setConnectedHeartbeat(bloc, null);
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.eshStatus == EshSystemStatus.unknown,
      );

      bloc.add(turnOnTerasLampu());
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.commandErrors[terasLampu] ==
                'Status ESH belum tersedia. Perintah tidak dikirim',
      );

      expect(repository.lastRoomKey, isNull);
    },
  );

  test('command is rejected when ESH heartbeat is offline', () async {
    bloc.add(DeviceStateUpdated(roomState(lampu: false)));
    await waitForState(bloc, (state) => state is MonitoringLoaded);
    await setConnectedHeartbeat(bloc, nowEpochSeconds - 60);
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.eshStatus == EshSystemStatus.offline,
    );

    bloc.add(turnOnTerasLampu());
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.commandErrors[terasLampu] ==
              'Sistem ESH offline. Perintah tidak dikirim',
    );

    expect(repository.lastRoomKey, isNull);
  });

  test('command is sent only when Firebase and ESH are online', () async {
    bloc.add(DeviceStateUpdated(roomState(lampu: false)));
    await waitForState(bloc, (state) => state is MonitoringLoaded);
    await setConnectedHeartbeat(bloc, nowEpochSeconds - 59);
    await waitForState(
      bloc,
      (state) => state is MonitoringLoaded && state.canControl,
    );

    bloc.add(turnOnTerasLampu());
    await waitForState(bloc, (_) => repository.lastRoomKey == 'teras');

    expect(repository.lastIsOn, isTrue);
  });

  test('master route remains allowed when Slave is offline', () async {
    bloc.add(DeviceStateUpdated(roomState(lampu: false)));
    await waitForState(bloc, (state) => state is MonitoringLoaded);
    await setConnectedHeartbeat(bloc, nowEpochSeconds);
    bloc.add(SlaveAvailabilityChanged(false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.canControl &&
          state.slaveOnline == false,
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.canControlDevice(terasLampu), isTrue);
    bloc.add(turnOnTerasLampu());
    await waitForState(bloc, (_) => repository.lastRoomKey == 'teras');

    expect(repository.controlCallCount, 1);
  });

  for (final slaveOnline in <bool?>[false, null]) {
    test('slave route is rejected when availability is $slaveOnline', () async {
      bloc.add(
        DeviceStateUpdated(
          RoomDeviceCollection.empty().set(
            dapurBlower,
            const RoomDeviceValue(isOn: false),
          ),
        ),
      );
      await waitForState(bloc, (state) => state is MonitoringLoaded);
      await setConnectedHeartbeat(bloc, nowEpochSeconds);
      bloc.add(SlaveAvailabilityChanged(slaveOnline));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded && state.slaveOnline == slaveOnline,
      );

      bloc.add(turnOnDapurBlower());
      final expectedReason = slaveOnline == null
          ? 'Status Slave belum tersedia. Perintah tidak dikirim'
          : 'Slave tidak tersedia. Perintah tidak dikirim';
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded &&
            state.commandErrors[dapurBlower] == expectedReason,
      );

      final state = bloc.state as MonitoringLoaded;
      expect(state.canControl, isTrue);
      expect(state.canControlDevice(dapurBlower), isFalse);
      expect(state.pendingDevices, isEmpty);
      expect(state.desiredDevices, isNot(contains(dapurBlower)));
      expect(repository.controlCallCount, 0);
    });
  }

  test('slave route is allowed when Slave is online', () async {
    bloc.add(
      DeviceStateUpdated(
        RoomDeviceCollection.empty().set(
          dapurBlower,
          const RoomDeviceValue(isOn: false),
        ),
      ),
    );
    await waitForState(bloc, (state) => state is MonitoringLoaded);
    await setConnectedHeartbeat(bloc, nowEpochSeconds);
    bloc.add(SlaveAvailabilityChanged(true));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded && state.canControlDevice(dapurBlower),
    );

    bloc.add(turnOnDapurBlower());
    await waitForState(bloc, (_) => repository.lastRoomKey == 'dapur');

    expect(repository.lastDeviceKey, 'blower');
    expect(repository.controlCallCount, 1);
  });

  test('matching room update confirms pending command', () async {
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(roomState(lampu: false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded && state.deviceData.values.isNotEmpty,
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
    'offline command is rejected without pending or repository write',
    () async {
      bloc.add(DeviceStateUpdated(roomState(lampu: false)));
      await waitForState(
        bloc,
        (state) => state is MonitoringLoaded && !state.isConnected,
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
      expect(repository.lastRoomKey, isNull);
    },
  );

  test('no-op command refreshes persistent desired without pending', () async {
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(roomState(lampu: false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.deviceData.find(terasLampu) != null,
    );

    bloc.add(
      ControlRoomDevice(
        roomName: 'Teras',
        roomKey: 'teras',
        deviceName: 'Lampu',
        deviceKey: 'lampu',
        isOn: false,
        brightness: 0,
        supportsBrightness: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = bloc.state as MonitoringLoaded;
    expect(state.pendingDevices, isEmpty);
    expect(repository.lastRoomKey, 'teras');
    expect(repository.lastIsOn, isFalse);
  });

  test('late no-op failure does not clear newer pending command', () async {
    final firstWrite = Completer<void>();
    repository.controlHandler = (call) {
      if (call == 1) return firstWrite.future;
      return Future<void>.value();
    };
    bloc.add(DeviceStateUpdated(roomState(lampu: false)));
    await waitForState(bloc, (state) => state is MonitoringLoaded);
    await setConnectedHeartbeat(bloc, nowEpochSeconds);
    await waitForState(
      bloc,
      (state) => state is MonitoringLoaded && state.canControl,
    );

    bloc.add(
      ControlRoomDevice(
        roomName: 'Teras',
        roomKey: 'teras',
        deviceName: 'Lampu',
        deviceKey: 'lampu',
        isOn: false,
        brightness: 0,
        supportsBrightness: false,
      ),
    );
    await waitForState(bloc, (_) => repository.controlCallCount == 1);

    bloc.add(turnOnTerasLampu());
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.pendingDevices.contains(terasLampu),
    );
    firstWrite.completeError(Exception('late failure'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = bloc.state as MonitoringLoaded;
    expect(state.pendingDevices, contains(terasLampu));
    expect(state.commandErrors, isNot(contains(terasLampu)));
  });

  test('actual no-op overwrites conflicting persistent desired', () async {
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(roomState(lampu: false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.deviceData.find(terasLampu) != null,
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
    bloc.add(ClearPendingCommand(terasLampu));
    await waitForState(
      bloc,
      (state) => state is MonitoringLoaded && state.pendingDevices.isEmpty,
    );

    repository.lastRoomKey = null;
    bloc.add(
      ControlRoomDevice(
        roomName: 'Teras',
        roomKey: 'teras',
        deviceName: 'Lampu',
        deviceKey: 'lampu',
        isOn: false,
        brightness: 0,
        supportsBrightness: false,
      ),
    );
    await waitForState(bloc, (_) => repository.lastRoomKey == 'teras');

    expect(repository.lastIsOn, isFalse);
  });

  test('shared brightness marks both bedroom lamps pending', () async {
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(
      RoomDeviceCollection.empty()
          .set(kamar1Lampu, const RoomDeviceValue(isOn: false, brightness: 20))
          .set(kamar2Lampu, const RoomDeviceValue(isOn: true, brightness: 20)),
    );
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded && state.deviceData.values.length == 2,
    );

    bloc.add(
      ControlRoomDevice(
        roomName: 'Kamar 1',
        roomKey: 'kamar_1',
        deviceName: 'Lampu',
        deviceKey: 'lampu',
        isOn: true,
        brightness: 60,
        supportsBrightness: true,
      ),
    );
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.pendingDevices.contains(kamar1Lampu) &&
          state.pendingDevices.contains(kamar2Lampu),
    );

    final state = bloc.state as MonitoringLoaded;
    expect(
      state.desiredDevices[kamar1Lampu],
      const RoomDeviceValue(isOn: true, brightness: 60),
    );
    expect(
      state.desiredDevices[kamar2Lampu],
      const RoomDeviceValue(isOn: true, brightness: 60),
    );
  });

  test(
    'pending command does not optimistically mutate actual device data',
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
            state is MonitoringLoaded && state.deviceData.values.isNotEmpty,
      );

      bloc.add(
        ControlRoomDevice(
          roomName: 'Teras',
          roomKey: 'teras',
          deviceName: 'Lampu',
          deviceKey: 'lampu',
          isOn: true,
          brightness: 0,
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
        const RoomDeviceValue(isOn: false, brightness: 20),
      );
      expect(
        state.desiredDevices[terasLampu],
        const RoomDeviceValue(isOn: true, brightness: 1),
      );
      expect(repository.lastBrightness, 1);
      expect(repository.lastIsOn, isTrue);
      expect(repository.lastRoomKey, 'teras');
      expect(repository.lastDeviceKey, 'lampu');
    },
  );

  test('off dimmer retains normalized brightness', () async {
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(
      RoomDeviceCollection.empty().set(
        terasLampu,
        const RoomDeviceValue(isOn: true, brightness: 35),
      ),
    );
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.deviceData.find(terasLampu) != null,
    );

    bloc.add(
      ControlRoomDevice(
        roomName: 'Teras',
        roomKey: 'teras',
        deviceName: 'Lampu',
        deviceKey: 'lampu',
        isOn: false,
        brightness: 35,
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
      const RoomDeviceValue(isOn: true, brightness: 35),
    );
    expect(
      state.desiredDevices[terasLampu],
      const RoomDeviceValue(isOn: false, brightness: 35),
    );
    expect(repository.lastBrightness, 35);
  });

  test(
    'unrelated confirmed update does not erase another pending command',
    () async {
      bloc.add(StartMonitoring());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repository.roomsController.add(roomState(lampu: false, sanyo: false));
      await waitForState(
        bloc,
        (state) =>
            state is MonitoringLoaded && state.deviceData.values.length == 2,
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
      expect(state.deviceData.find(terasLampu)?.isOn, isFalse);
      expect(state.deviceData.find(terasSanyo)?.isOn, isTrue);
      expect(
        state.desiredDevices,
        containsPair(terasLampu, const RoomDeviceValue(isOn: true)),
      );
      expect(state.desiredDevices, isNot(contains(terasSanyo)));
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
          state is MonitoringLoaded && state.deviceData.values.isNotEmpty,
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
            state.deviceData.find(terasLampu) != null,
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
        timeout: const Duration(seconds: 2),
      );

      final state = bloc.state as MonitoringLoaded;
      expect(state.pendingDevices, isEmpty);
      expect(state.deviceData.find(terasLampu)?.isOn, isFalse);
      expect(
        state.commandErrors[terasLampu],
        'Perintah tidak dikonfirmasi perangkat',
      );
      expect(
        state.desiredDevices[terasLampu],
        const RoomDeviceValue(isOn: true),
      );
    },
  );

  test('timeout starts before a hanging write completes', () async {
    repository.controlCompleter = Completer<void>();
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(roomState(lampu: false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.deviceData.find(terasLampu) != null,
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
          state.commandErrors[terasLampu] ==
              'Perintah tidak dikonfirmasi perangkat',
      timeout: const Duration(seconds: 2),
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.pendingDevices, isEmpty);
    expect(state.deviceData.find(terasLampu)?.isOn, isFalse);
    repository.controlCompleter!.complete();
  });

  test('fresh online data triggers canonical sensor log write', () async {
    final historyRepository = FakeHistoryRepositoryForBloc();
    await bloc.close();
    bloc = createMonitoringBloc(
      repository,
      saveSensorLog: SaveSensorLogUseCase(repository: historyRepository),
    );

    final data = McbDataCollection(
      heartbeatEpochSeconds: nowEpochSeconds,
      mcb1: const McbData(
        connected: true,
        voltage: 220,
        current: 1,
        power: 220,
        energy: 1.5,
        sampledAtEpochSeconds: nowEpochSeconds,
      ),
      sensorData: const SensorData(
        temperature: 28,
        humidity: 60,
        connected: true,
        sampledAtEpochSeconds: nowEpochSeconds,
      ),
    );
    bloc.add(DataUpdated(data));
    bloc.add(ConnectionStatusChanged(true));
    await waitForState(bloc, (state) => state is MonitoringLoaded && state.canControl);

    expect(historyRepository.savedCollection, isNotNull);
    expect(historyRepository.savedCollection!.totalEnergy, 1.5);
  });

  test('sensor log write is skipped when ESH is offline', () async {
    final historyRepository = FakeHistoryRepositoryForBloc();
    await bloc.close();
    bloc = createMonitoringBloc(
      repository,
      saveSensorLog: SaveSensorLogUseCase(repository: historyRepository),
    );

    await setConnectedHeartbeat(bloc, nowEpochSeconds - 60);
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.eshStatus == EshSystemStatus.offline,
    );

    expect(historyRepository.savedCollection, isNull);
  });

  test('late matching room update clears timeout error', () async {
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add(roomState(lampu: false));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          state.deviceData.find(terasLampu) != null,
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
      timeout: const Duration(seconds: 2),
    );

    repository.roomsController.add(roomState(lampu: true));
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded &&
          !state.commandErrors.containsKey(terasLampu),
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.deviceData.find(terasLampu)?.isOn, isTrue);
    expect(state.desiredDevices, isNot(contains(terasLampu)));
  });
}
