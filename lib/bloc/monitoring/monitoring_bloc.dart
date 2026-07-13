import 'dart:async';
import 'package:esh/models/model.dart';
import 'package:esh/services/firebase_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'monitoring_event.dart';
import 'monitoring_state.dart';

class MonitoringBloc extends Bloc<MonitoringEvent, MonitoringState> {
  static const pendingCommandTimeout = Duration(seconds: 5);

  final MonitoringRepository firebaseService;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _deviceDataSubscription;
  final Map<String, Timer> _pendingTimers = {};
  bool _monitoringActive = false;

  MonitoringBloc({required this.firebaseService}) : super(MonitoringInitial()) {
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

    final pendingKey = '${event.roomKey}/${event.deviceKey}';
    if (currentState.pendingDevices.contains(pendingKey)) return;

    final pendingDevices = Set<String>.from(currentState.pendingDevices)
      ..add(pendingKey);
    final commandErrors = Map<String, String>.from(currentState.commandErrors)
      ..remove(pendingKey);
    final optimisticData = _buildOptimisticDeviceData(
      currentState.deviceData,
      event.roomKey,
      event.deviceKey,
      event.isOn,
      event.brightness,
      event.supportsBrightness,
    );

    emit(
      currentState.copyWith(
        deviceData: optimisticData,
        pendingDevices: pendingDevices,
        commandErrors: commandErrors,
      ),
    );

    _pendingTimers[pendingKey]?.cancel();
    _pendingTimers[pendingKey] = Timer(pendingCommandTimeout, () {
      if (!isClosed) add(ClearPendingCommand(pendingKey));
    });

    try {
      await firebaseService.controlRoomDevice(
        event.roomKey,
        event.deviceKey,
        event.isOn,
        event.brightness.toInt(),
        event.supportsBrightness,
      );
    } catch (_) {
      if (!isClosed) {
        add(CommandFailed(pendingKey, 'Perintah gagal dikirim'));
      }
    }
  }

  Map<String, dynamic> _buildOptimisticDeviceData(
    Map<String, dynamic> currentData,
    String roomKey,
    String deviceKey,
    bool isOn,
    double brightness,
    bool supportsBrightness,
  ) {
    final data = Map<String, dynamic>.from(currentData);
    final rooms = data['rooms'] is Map
        ? Map<String, dynamic>.from(data['rooms'] as Map)
        : <String, dynamic>{};
    final room = rooms[roomKey] is Map
        ? Map<String, dynamic>.from(rooms[roomKey] as Map)
        : <String, dynamic>{};

    room[deviceKey] = supportsBrightness
        ? <String, dynamic>{
            'state': isOn,
            'brightness': isOn ? brightness.toInt().clamp(0, 100) : 0,
          }
        : isOn;
    rooms[roomKey] = room;
    data['rooms'] = rooms;
    return data;
  }

  Future<void> _onStartMonitoring(
    StartMonitoring event,
    Emitter<MonitoringState> emit,
  ) async {
    if (_monitoringActive) return;
    emit(MonitoringLoading());

    try {
      await _cancelSubscriptions();
      _dataSubscription = firebaseService.getMonitoringDataStream().listen(
        (mcbData) => add(DataUpdated(mcbData)),
        onError: (Object error) {
          if (!isClosed) {
            add(MonitoringStreamFailed('Data monitoring tidak tersedia'));
          }
        },
      );
      _connectionSubscription = firebaseService.getConnectionStatus().listen(
        (isConnected) => add(ConnectionStatusChanged(isConnected)),
        onError: (Object error) {
          if (!isClosed) add(ConnectionStatusChanged(false));
        },
      );
      _deviceDataSubscription = firebaseService.getRoomDevicesStream().listen(
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
      final confirmedData = _deepCopyMap(event.data);
      emit(
        MonitoringLoaded(
          mcbData: McbDataCollection.empty(),
          isConnected: false,
          deviceData: confirmedData,
          confirmedDeviceData: confirmedData,
        ),
      );
      return;
    }

    final confirmedData = _deepCopyMap(event.data);
    final mergedData = _deepCopyMap(confirmedData);
    final pendingDevices = Set<String>.from(currentState.pendingDevices);
    final commandErrors = Map<String, String>.from(currentState.commandErrors);

    for (final pendingKey in currentState.pendingDevices) {
      final parts = pendingKey.split('/');
      if (parts.length != 2) continue;
      final roomKey = parts[0];
      final deviceKey = parts[1];
      final desired = _deviceNode(currentState.deviceData, roomKey, deviceKey);
      final confirmed = _deviceNode(confirmedData, roomKey, deviceKey);

      if (_deviceValuesMatch(desired, confirmed)) {
        pendingDevices.remove(pendingKey);
        commandErrors.remove(pendingKey);
        _pendingTimers.remove(pendingKey)?.cancel();
      } else if (desired != null) {
        _setDeviceNode(mergedData, roomKey, deviceKey, desired);
      }
    }

    emit(
      currentState.copyWith(
        deviceData: mergedData,
        confirmedDeviceData: confirmedData,
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
        !currentState.pendingDevices.contains(event.pendingKey)) {
      return;
    }

    final pendingDevices = Set<String>.from(currentState.pendingDevices)
      ..remove(event.pendingKey);
    final commandErrors = Map<String, String>.from(currentState.commandErrors)
      ..[event.pendingKey] = 'Perintah tidak dikonfirmasi perangkat';
    _pendingTimers.remove(event.pendingKey)?.cancel();

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

    final pendingDevices = Set<String>.from(currentState.pendingDevices)
      ..remove(event.pendingKey);
    final commandErrors = Map<String, String>.from(currentState.commandErrors)
      ..[event.pendingKey] = event.message;
    _pendingTimers.remove(event.pendingKey)?.cancel();

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

  Map<String, dynamic> _restorePendingValues(
    MonitoringLoaded currentState,
    Set<String> pendingDevices,
  ) {
    final data = _deepCopyMap(currentState.confirmedDeviceData);
    for (final pendingKey in pendingDevices) {
      final parts = pendingKey.split('/');
      if (parts.length != 2) continue;
      final desired = _deviceNode(currentState.deviceData, parts[0], parts[1]);
      if (desired != null) {
        _setDeviceNode(data, parts[0], parts[1], desired);
      }
    }
    return data;
  }

  dynamic _deviceNode(
    Map<String, dynamic> data,
    String roomKey,
    String deviceKey,
  ) {
    final rooms = data['rooms'];
    if (rooms is! Map) return null;
    final room = rooms[roomKey];
    if (room is! Map) return null;
    return room[deviceKey];
  }

  void _setDeviceNode(
    Map<String, dynamic> data,
    String roomKey,
    String deviceKey,
    dynamic value,
  ) {
    final rooms = data['rooms'] is Map
        ? Map<String, dynamic>.from(data['rooms'] as Map)
        : <String, dynamic>{};
    final room = rooms[roomKey] is Map
        ? Map<String, dynamic>.from(rooms[roomKey] as Map)
        : <String, dynamic>{};
    room[deviceKey] = value is Map ? Map<String, dynamic>.from(value) : value;
    rooms[roomKey] = room;
    data['rooms'] = rooms;
  }

  bool _deviceValuesMatch(dynamic desired, dynamic confirmed) {
    if (desired is bool && confirmed is bool) return desired == confirmed;
    if (desired is Map && confirmed is Map) {
      final desiredBrightness = desired['brightness'];
      final confirmedBrightness = confirmed['brightness'];
      return desired['state'] == confirmed['state'] &&
          desiredBrightness is num &&
          confirmedBrightness is num &&
          desiredBrightness.toInt() == confirmedBrightness.toInt();
    }
    return false;
  }

  Map<String, dynamic> _deepCopyMap(Map<dynamic, dynamic> source) {
    final result = <String, dynamic>{};
    source.forEach((key, value) {
      result[key.toString()] = value is Map ? _deepCopyMap(value) : value;
    });
    return result;
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
