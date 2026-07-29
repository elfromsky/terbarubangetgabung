import 'dart:async';

import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
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
  final Map<DeviceAddress, int> _commandGenerations = {};
  int _nextCommandGeneration = 0;
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

    if (!currentState.isConnected) {
      final errors = Map<DeviceAddress, String>.from(currentState.commandErrors)
        ..[address] = 'Firebase terputus. Perintah tidak dikirim';
      emit(currentState.copyWith(commandErrors: errors));
      return;
    }

    var normalizedBrightness = event.brightness.toInt().clamp(0, 100);
    if (event.supportsBrightness && event.isOn && normalizedBrightness == 0) {
      normalizedBrightness = 1;
    }
    final desiredValue = event.supportsBrightness
        ? RoomDeviceValue(isOn: event.isOn, brightness: normalizedBrightness)
        : RoomDeviceValue(isOn: event.isOn);
    final desiredByAddress = <DeviceAddress, RoomDeviceValue>{
      address: desiredValue,
    };

    final pairAddress = _sharedDimmerPair(address, event.supportsBrightness);
    if (pairAddress != null) {
      final pairValue = currentState.deviceData.find(pairAddress);
      if (pairValue == null) {
        final errors = Map<DeviceAddress, String>.from(
          currentState.commandErrors,
        )..[address] = 'Status lampu pasangan belum tersedia';
        emit(currentState.copyWith(commandErrors: errors));
        return;
      }
      if (currentState.pendingDevices.contains(pairAddress)) return;
      desiredByAddress[pairAddress] = RoomDeviceValue(
        isOn: pairValue.isOn,
        brightness: normalizedBrightness,
      );
    }

    if (desiredByAddress.entries.every(
      (entry) => currentState.deviceData.find(entry.key) == entry.value,
    )) {
      final errors = Map<DeviceAddress, String>.from(currentState.commandErrors)
        ..remove(address);
      emit(currentState.copyWith(commandErrors: errors));
      try {
        await controlRoomDevice(
          roomKey: event.roomKey,
          deviceKey: event.deviceKey,
          isOn: event.isOn,
          brightness: normalizedBrightness,
          supportsBrightness: event.supportsBrightness,
        );
      } catch (_) {
        if (!isClosed) {
          add(CommandFailed(address, 'Perintah gagal dikirim'));
        }
      }
      return;
    }

    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
      ..addAll(desiredByAddress.keys);
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    )..removeWhere((key, _) => desiredByAddress.containsKey(key));
    final desiredDevices = Map<DeviceAddress, RoomDeviceValue>.from(
      currentState.desiredDevices,
    )..addAll(desiredByAddress);
    final generations = <DeviceAddress, int>{};
    for (final target in desiredByAddress.keys) {
      final generation = ++_nextCommandGeneration;
      _commandGenerations[target] = generation;
      generations[target] = generation;
    }

    emit(
      currentState.copyWith(
        desiredDevices: desiredDevices,
        pendingDevices: pendingDevices,
        commandErrors: commandErrors,
      ),
    );

    for (final entry in generations.entries) {
      _pendingTimers[entry.key]?.cancel();
      _pendingTimers[entry.key] = Timer(pendingCommandTimeout, () {
        if (!isClosed) add(ClearPendingCommand(entry.key, entry.value));
      });
    }

    try {
      await controlRoomDevice(
        roomKey: event.roomKey,
        deviceKey: event.deviceKey,
        isOn: event.isOn,
        brightness: normalizedBrightness,
        supportsBrightness: event.supportsBrightness,
      );
    } catch (_) {
      if (!isClosed) {
        for (final entry in generations.entries) {
          add(CommandFailed(entry.key, 'Perintah gagal dikirim', entry.value));
        }
      }
    }
  }

  DeviceAddress? _sharedDimmerPair(
    DeviceAddress address,
    bool supportsBrightness,
  ) {
    if (!supportsBrightness || address.deviceKey != 'lampu') return null;
    if (address.roomKey == 'kamar_1') {
      return const DeviceAddress(roomKey: 'kamar_2', deviceKey: 'lampu');
    }
    if (address.roomKey == 'kamar_2') {
      return const DeviceAddress(roomKey: 'kamar_1', deviceKey: 'lampu');
    }
    return null;
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
        ),
      );
      return;
    }

    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices);
    final desiredDevices = Map<DeviceAddress, RoomDeviceValue>.from(
      currentState.desiredDevices,
    );
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    );

    for (final entry in currentState.desiredDevices.entries) {
      final address = entry.key;
      final desired = entry.value;
      final confirmed = event.data.find(address);

      if (desired == confirmed) {
        pendingDevices.remove(address);
        desiredDevices.remove(address);
        commandErrors.remove(address);
        _pendingTimers.remove(address)?.cancel();
        _commandGenerations.remove(address);
      }
    }

    emit(
      currentState.copyWith(
        deviceData: event.data,
        desiredDevices: desiredDevices,
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
        !currentState.pendingDevices.contains(event.address) ||
        (event.generation != 0 &&
            _commandGenerations[event.address] != event.generation)) {
      return;
    }

    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
      ..remove(event.address);
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    )..[event.address] = 'Perintah tidak dikonfirmasi perangkat';
    _pendingTimers.remove(event.address)?.cancel();
    _commandGenerations.remove(event.address);

    emit(
      currentState.copyWith(
        pendingDevices: pendingDevices,
        commandErrors: commandErrors,
      ),
    );
  }

  void _onCommandFailed(CommandFailed event, Emitter<MonitoringState> emit) {
    final currentState = state;
    if (currentState is! MonitoringLoaded ||
        (event.generation != 0 &&
            _commandGenerations[event.address] != event.generation)) {
      return;
    }

    final pendingDevices = Set<DeviceAddress>.from(currentState.pendingDevices)
      ..remove(event.address);
    final commandErrors = Map<DeviceAddress, String>.from(
      currentState.commandErrors,
    )..[event.address] = event.message;
    _pendingTimers.remove(event.address)?.cancel();
    _commandGenerations.remove(event.address);

    emit(
      currentState.copyWith(
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
    _commandGenerations.clear();
  }

  @override
  Future<void> close() async {
    await _cancelSubscriptions();
    _cancelPendingTimers();
    return super.close();
  }
}
