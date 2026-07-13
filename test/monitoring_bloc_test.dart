import 'dart:async';

import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/bloc/monitoring/monitoring_state.dart';
import 'package:esh/models/model.dart';
import 'package:esh/services/firebase_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonitoringRepository implements MonitoringRepository {
  final monitoringController = StreamController<McbDataCollection>.broadcast();
  final roomsController = StreamController<Map<String, dynamic>>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  int monitoringListeners = 0;
  bool failControl = false;

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
  Stream<Map<String, dynamic>> getRoomDevicesStream() => roomsController.stream;

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
    if (failControl) throw Exception('write failed');
  }

  Future<void> close() async {
    await monitoringController.close();
    await roomsController.close();
    await connectionController.close();
  }
}

Future<void> waitForState(
  MonitoringBloc bloc,
  bool Function(MonitoringState state) predicate,
) async {
  if (predicate(bloc.state)) return;
  await bloc.stream.firstWhere(predicate).timeout(const Duration(seconds: 2));
}

void main() {
  late FakeMonitoringRepository repository;
  late MonitoringBloc bloc;

  setUp(() {
    repository = FakeMonitoringRepository();
    bloc = MonitoringBloc(firebaseService: repository);
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
    repository.roomsController.add({
      'rooms': {
        'teras': {'lampu': false},
      },
    });
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded && state.confirmedDeviceData.isNotEmpty,
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
          state.pendingDevices.contains('teras/lampu'),
    );

    repository.roomsController.add({
      'rooms': {
        'teras': {'lampu': true},
      },
    });
    await waitForState(
      bloc,
      (state) => state is MonitoringLoaded && state.pendingDevices.isEmpty,
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.commandErrors, isEmpty);
    expect(state.deviceData['rooms']['teras']['lampu'], isTrue);
  });

  test('write failure rolls back to confirmed room state', () async {
    repository.failControl = true;
    bloc.add(StartMonitoring());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repository.roomsController.add({
      'rooms': {
        'teras': {'lampu': false},
      },
    });
    await waitForState(
      bloc,
      (state) =>
          state is MonitoringLoaded && state.confirmedDeviceData.isNotEmpty,
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
          state.commandErrors.containsKey('teras/lampu'),
    );

    final state = bloc.state as MonitoringLoaded;
    expect(state.pendingDevices, isEmpty);
    expect(state.deviceData['rooms']['teras']['lampu'], isFalse);
  });
}
