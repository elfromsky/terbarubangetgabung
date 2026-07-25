import 'dart:async';

import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'monitoring_event.dart';
import 'monitoring_state.dart';

class MonitoringBloc extends Bloc<MonitoringEvent, MonitoringState> {
  static const pendingCommandTimeout = Duration(seconds: 5);

  final WatchMonitoringDataUseCase watchMonitoringData;
  final WatchConnectionStatusUseCase watchConnectionStatus;
  final WatchRoomDevicesUseCase watchRoomDevices;
  final ControlRoomDeviceUseCase controlRoomDevice;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _deviceDataSubscription;
  final Map<DeviceAddress, Timer> _pendingTimers = {};
  bool _monitoringActive = false;

  MonitoringBloc({
    required this.watchMonitoringData,
    required this.watchConnectionStatus,
    required this.watchRoomDevices,
    required this.controlRoomDevice,
  }) : super(MonitoringInitial()) {
    on<StartMonitoring>(_onStartMonitoring);
    on<StopMonitoring>(_onStopMonitoring);
    on<DataUpdated>(_onDataUpdated);
    on<ConnectionStatusChanged>(_onConnectionStatusChanged);
    on<ControlRoomDevice>(_onControlRoomDevice);
    on<DeviceStateUpdated>(_onDeviceStateUpdated);
    on<ClearPendingCommand>(_onClearPendingCommand);
    on<MonitoringStreamFailed>(_onMonitoringStreamFailed);
    on<CommandFailed>(_onCommandFailed);
  }

  Future<void> _onControlRoomDevice(
    ControlRoomDevice event,
    Emitter<MonitoringState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MonitoringLoaded) return;

    final address = DeviceAddress(
      roomKey: event.roomKey,
      deviceKey: event.deviceKey,
    );
    if (currentState.pendingDevices.contains(address)) return;

    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
      ..add(address);
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    )..remove(address);
    final normalizedBrightness = event.brightness.toInt().clamp(0, 100);
    final optimisticData = _buildOptimisticDeviceData(
      currentState.deviceData,
      address,
      event.isOn,
      normalizedBrightness,
      event.supportsBrightness,
    );

    emit(
      currentState.copyWith(
        deviceData: optimisticData,
        pendingDevices: pendingDevices,
        commandErrors: commandErrors,
      ),
    );

    _pendingTimers[address]?.cancel();

    try {
      await controlRoomDevice(
        roomKey: event.roomKey,
        deviceKey: event.deviceKey,
        isOn: event.isOn,
        brightness: normalizedBrightness,
        supportsBrightness: event.supportsBrightness,
      );
      _pendingTimers[address] = Timer(pendingCommandTimeout, () {
        if (!isClosed) add(ClearPendingCommand(address));
      });
    } catch (_) {
      if (!isClosed) {
        add(CommandFailed(address, 'Perintah gagal dikirim'));
      }
    }
  }

  RoomDeviceCollection _buildOptimisticDeviceData(
    RoomDeviceCollection currentData,
    DeviceAddress address,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) {
    final value = supportsBrightness
        ? RoomDeviceValue(isOn: isOn, brightness: isOn ? brightness : 0)
        : RoomDeviceValue(isOn: isOn);
    return currentData.set(address, value);
  }

  Future<void> _onStartMonitoring(
    StartMonitoring event,
    Emitter<MonitoringState> emit,
  ) async {
    if (_monitoringActive) return;
    emit(MonitoringLoading());

    try {
      await _cancelSubscriptions();
      _dataSubscription = watchMonitoringData().listen(
        (mcbData) => add(DataUpdated(mcbData)),
        onError: (Object error) {
          if (!isClosed) {
            add(MonitoringStreamFailed('Data monitoring tidak tersedia'));
          }
        },
      );
      _connectionSubscription = watchConnectionStatus().listen(
        (isConnected) => add(ConnectionStatusChanged(isConnected)),
        onError: (Object error) {
          if (!isClosed) add(ConnectionStatusChanged(false));
        },
      );
      _deviceDataSubscription = watchRoomDevices().listen(
        (data) => add(DeviceStateUpdated(data)),
        onError: (Object error) {
          if (!isClosed) {
            add(MonitoringStreamFailed('Status perangkat tidak tersedia'));
          }
        },
      );
      _monitoringActive = true;
    } catch (_) {
      _monitoringActive = false;
      emit(MonitoringError('Monitoring gagal dimulai'));
    }
  }

  Future<void> _onStopMonitoring(
    StopMonitoring event,
    Emitter<MonitoringState> emit,
  ) async {
    await _cancelSubscriptions();
    _cancelPendingTimers();
    emit(MonitoringInitial());
  }

  void _onDataUpdated(DataUpdated event, Emitter<MonitoringState> emit) {
    final currentState = state;
    if (currentState is MonitoringLoaded) {
      emit(currentState.copyWith(mcbData: event.mcbData));
    } else {
      emit(MonitoringLoaded(mcbData: event.mcbData, isConnected: false));
    }
  }

  void _onConnectionStatusChanged(
    ConnectionStatusChanged event,
    Emitter<MonitoringState> emit,
  ) {
    final currentState = state;
    if (currentState is MonitoringLoaded) {
      emit(currentState.copyWith(isConnected: event.isConnected));
    } else {
      emit(
        MonitoringLoaded(
          mcbData: McbDataCollection.empty(),
          isConnected: event.isConnected,
        ),
      );
    }
  }

  void _onDeviceStateUpdated(
    DeviceStateUpdated event,
    Emitter<MonitoringState> emit,
  ) {
    final currentState = state;
    if (currentState is! MonitoringLoaded) {
      emit(
        MonitoringLoaded(
          mcbData: McbDataCollection.empty(),
          isConnected: false,
          deviceData: event.data,
          confirmedDeviceData: event.data,
        ),
      );
      return;
    }

    var visibleData = event.data;
    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices);
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    );

    for (final address in currentState.pendingDevices) {
      final desired = currentState.deviceData.find(address);
      final confirmed = event.data.find(address);

      if (desired != null && desired == confirmed) {
        pendingDevices.remove(address);
        commandErrors.remove(address);
        _pendingTimers.remove(address)?.cancel();
      } else if (desired != null) {
        visibleData = visibleData.set(address, desired);
      }
    }

    emit(
      currentState.copyWith(
        deviceData: visibleData,
        confirmedDeviceData: event.data,
        pendingDevices: pendingDevices,
        commandErrors: commandErrors,
      ),
    );
  }

  void _onClearPendingCommand(
    ClearPendingCommand event,
    Emitter<MonitoringState> emit,
  ) {
    final currentState = state;
    if (currentState is! MonitoringLoaded ||
        !currentState.pendingDevices.contains(event.address)) {
      return;
    }

    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
      ..remove(event.address);
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    )..[event.address] = 'Perintah tidak dikonfirmasi perangkat';
    _pendingTimers.remove(event.address)?.cancel();

    emit(
      currentState.copyWith(
        deviceData: _restorePendingValues(currentState, pendingDevices),
        pendingDevices: pendingDevices,
        commandErrors: commandErrors,
      ),
    );
  }

  void _onCommandFailed(CommandFailed event, Emitter<MonitoringState> emit) {
    final currentState = state;
    if (currentState is! MonitoringLoaded) return;

    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
      ..remove(event.address);
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    )..[event.address] = event.message;
    _pendingTimers.remove(event.address)?.cancel();

    emit(
      currentState.copyWith(
        deviceData: _restorePendingValues(currentState, pendingDevices),
        pendingDevices: pendingDevices,
        commandErrors: commandErrors,
      ),
    );
  }

  void _onMonitoringStreamFailed(
    MonitoringStreamFailed event,
    Emitter<MonitoringState> emit,
  ) {
    _monitoringActive = false;
    final currentState = state;
    if (currentState is MonitoringLoaded) {
      emit(currentState.copyWith(isConnected: false));
    } else {
      emit(MonitoringError(event.message));
    }
  }

  RoomDeviceCollection _restorePendingValues(
    MonitoringLoaded currentState,
    Set<DeviceAddress> pendingDevices,
  ) {
    var data = currentState.confirmedDeviceData;
    for (final address in pendingDevices) {
      final desired = currentState.deviceData.find(address);
      if (desired != null) data = data.set(address, desired);
    }
    return data;
  }

  Future<void> _cancelSubscriptions() async {
    _monitoringActive = false;
    await _dataSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _deviceDataSubscription?.cancel();
    _dataSubscription = null;
    _connectionSubscription = null;
    _deviceDataSubscription = null;
  }

  void _cancelPendingTimers() {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
  }

  @override
  Future<void> close() async {
    await _cancelSubscriptions();
    _cancelPendingTimers();
    return super.close();
  }
}
