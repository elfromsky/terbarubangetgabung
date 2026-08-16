import 'dart:async';

import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/history/domain/usecases/save_sensor_log_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_slave_availability_use_case.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'monitoring_event.dart';
import 'monitoring_state.dart';

class MonitoringBloc extends Bloc<MonitoringEvent, MonitoringState> {
  static const defaultPendingCommandTimeout = Duration(seconds: 12);
  static const eshHeartbeatLifetime = Duration(seconds: 60);

  final WatchMonitoringDataUseCase watchMonitoringData;
  final WatchConnectionStatusUseCase watchConnectionStatus;
  final WatchRoomDevicesUseCase watchRoomDevices;
  final WatchSlaveAvailabilityUseCase watchSlaveAvailability;
  final ControlRoomDeviceUseCase controlRoomDevice;
  final SaveSensorLogUseCase? saveSensorLog;
  final Duration pendingCommandTimeout;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _freshnessTimerFactory;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _deviceDataSubscription;
  StreamSubscription? _slaveAvailabilitySubscription;
  final Map<DeviceAddress, Timer> _pendingTimers = {};
  final Map<DeviceAddress, int> _commandGenerations = {};
  Timer? _freshnessExpiryTimer;
  int _freshnessGeneration = 0;
  int _nextCommandGeneration = 0;
  bool _monitoringActive = false;
  bool _monitoringStartInProgress = false;

  // Sensor-log writer throttling.
  static const sensorLogMinInterval = Duration(minutes: 5);
  static const sensorLogSignificantChange = 0.01; // kWh
  DateTime? _lastSensorLogTimestamp;
  McbDataCollection? _lastSensorLogCollection;

  MonitoringBloc({
    required this.watchMonitoringData,
    required this.watchConnectionStatus,
    required this.watchRoomDevices,
    required this.watchSlaveAvailability,
    required this.controlRoomDevice,
    this.saveSensorLog,
    this.pendingCommandTimeout = defaultPendingCommandTimeout,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? freshnessTimerFactory,
  }) : _now = now ?? DateTime.now,
       _freshnessTimerFactory =
           freshnessTimerFactory ??
           ((duration, callback) => Timer(duration, callback)),
       super(MonitoringInitial()) {
    on<StartMonitoring>(_onStartMonitoring);
    on<StopMonitoring>(_onStopMonitoring);
    on<DataUpdated>(_onDataUpdated);
    on<ConnectionStatusChanged>(_onConnectionStatusChanged);
    on<SlaveAvailabilityChanged>(_onSlaveAvailabilityChanged);
    on<MonitoringFreshnessExpired>(_onMonitoringFreshnessExpired);
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
    if (!currentState.canControlDevice(address)) {
      final errors = Map<DeviceAddress, String>.from(currentState.commandErrors)
        ..[address] = currentState.controlDisabledReasonFor(address)!;
      emit(currentState.copyWith(commandErrors: errors));
      return;
    }
    if (currentState.pendingDevices.contains(address)) return;

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
        ..removeWhere((key, _) => desiredByAddress.containsKey(key));
      final generations = <DeviceAddress, int>{};
      for (final target in desiredByAddress.keys) {
        final generation = ++_nextCommandGeneration;
        _commandGenerations[target] = generation;
        generations[target] = generation;
      }
      emit(currentState.copyWith(commandErrors: errors));
      try {
        await controlRoomDevice(
          roomKey: event.roomKey,
          deviceKey: event.deviceKey,
          isOn: event.isOn,
          brightness: normalizedBrightness,
          supportsBrightness: event.supportsBrightness,
        );
        for (final entry in generations.entries) {
          if (_commandGenerations[entry.key] == entry.value) {
            _commandGenerations.remove(entry.key);
          }
        }
      } catch (_) {
        if (!isClosed) {
          for (final entry in generations.entries) {
            add(
              CommandFailed(entry.key, 'Perintah gagal dikirim', entry.value),
            );
          }
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
    if (_monitoringActive || _monitoringStartInProgress) return;
    _monitoringStartInProgress = true;
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
      _slaveAvailabilitySubscription = watchSlaveAvailability().listen(
        (slaveOnline) => add(SlaveAvailabilityChanged(slaveOnline)),
        onError: (Object error) {
          if (!isClosed) add(SlaveAvailabilityChanged(null));
        },
      );
      _monitoringActive = true;
    } catch (_) {
      _monitoringActive = false;
      emit(MonitoringError('Monitoring gagal dimulai'));
    } finally {
      _monitoringStartInProgress = false;
    }
  }

  Future<void> _onStopMonitoring(
    StopMonitoring event,
    Emitter<MonitoringState> emit,
  ) async {
    await _cancelSubscriptions();
    _cancelPendingTimers();
    _cancelFreshnessExpiry();
    emit(MonitoringInitial());
  }

  void _onDataUpdated(DataUpdated event, Emitter<MonitoringState> emit) {
    final currentState = state;
    if (currentState is MonitoringLoaded) {
      final nextState = currentState.copyWith(mcbData: event.mcbData);
      emit(nextState.isConnected ? _recomputeFreshness(nextState) : nextState);
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
      if (!event.isConnected) {
        _cancelFreshnessExpiry();
        emit(currentState.copyWith(isConnected: false));
        return;
      }
      emit(_recomputeFreshness(currentState.copyWith(isConnected: true)));
    } else {
      final nextState = MonitoringLoaded(
        mcbData: McbDataCollection.empty(),
        isConnected: event.isConnected,
      );
      emit(event.isConnected ? _recomputeFreshness(nextState) : nextState);
    }
  }

  void _onMonitoringFreshnessExpired(
    MonitoringFreshnessExpired event,
    Emitter<MonitoringState> emit,
  ) {
    final currentState = state;
    if (currentState is! MonitoringLoaded ||
        !currentState.isConnected ||
        event.generation != _freshnessGeneration) {
      return;
    }
    emit(_recomputeFreshness(currentState));
  }

  void _onSlaveAvailabilityChanged(
    SlaveAvailabilityChanged event,
    Emitter<MonitoringState> emit,
  ) {
    final currentState = state;
    if (currentState is MonitoringLoaded) {
      emit(currentState.copyWith(slaveOnline: event.slaveOnline));
      return;
    }

    emit(
      MonitoringLoaded(
        mcbData: McbDataCollection.empty(),
        isConnected: false,
        slaveOnline: event.slaveOnline,
      ),
    );
  }

  MonitoringLoaded _recomputeFreshness(MonitoringLoaded state) {
    _cancelFreshnessExpiry();
    final now = _now();
    final heartbeat = state.mcbData.heartbeatEpochSeconds;
    final eshStatus = _eshStatusFor(heartbeat, now);
    final powerSampleFresh = _isFreshEpochSeconds(
      state.mcbData.mcb1.sampledAtEpochSeconds,
      now,
    );
    final environmentSampleFresh = _isFreshEpochSeconds(
      state.mcbData.sensorData.sampledAtEpochSeconds,
      now,
    );

    final freshTimestamps = <int>[
      if (eshStatus == EshSystemStatus.online) heartbeat!,
      if (state.mcbData.mcb1.connected && powerSampleFresh)
        state.mcbData.mcb1.sampledAtEpochSeconds!,
      if (state.mcbData.sensorData.connected && environmentSampleFresh)
        state.mcbData.sensorData.sampledAtEpochSeconds!,
    ];
    if (freshTimestamps.isNotEmpty) {
      final earliestExpiryEpochSeconds =
          freshTimestamps.reduce(
            (first, second) => first < second ? first : second,
          ) +
          eshHeartbeatLifetime.inSeconds;
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        earliestExpiryEpochSeconds * 1000,
      );
      final generation = _freshnessGeneration;
      _freshnessExpiryTimer = _freshnessTimerFactory(
        expiry.difference(now),
        () {
          if (!isClosed) add(MonitoringFreshnessExpired(generation));
        },
      );
    }

    final nextState = state.copyWith(
      eshStatus: eshStatus,
      isPowerSampleFresh: powerSampleFresh,
      isEnvironmentSampleFresh: environmentSampleFresh,
    );
    _maybeSaveSensorLog(nextState);
    return nextState;
  }

  void _maybeSaveSensorLog(MonitoringLoaded state) {
    if (saveSensorLog == null) return;
    if (!state.canControl) return;
    if (!state.mcbData.mcb1.connected || !state.isPowerSampleFresh) return;

    final now = _now();
    final last = _lastSensorLogCollection;
    final energyDelta =
        last == null
            ? double.infinity
            : (state.mcbData.totalEnergy - last.totalEnergy).abs();
    final intervalOk = _lastSensorLogTimestamp == null ||
        now.difference(_lastSensorLogTimestamp!) >= sensorLogMinInterval;

    if (!intervalOk && energyDelta < sensorLogSignificantChange) return;

    _lastSensorLogTimestamp = now;
    _lastSensorLogCollection = state.mcbData;

    saveSensorLog!(state.mcbData).catchError((Object error) {
      // Non-fatal: sensor logging must not break monitoring/control.
      if (!isClosed) {
        debugPrint('Sensor log write failed: $error');
      }
    });
  }

  EshSystemStatus _eshStatusFor(int? heartbeat, DateTime now) {
    if (heartbeat == null) return EshSystemStatus.unknown;
    final ageSeconds = now.millisecondsSinceEpoch ~/ 1000 - heartbeat;
    if (ageSeconds < 0) return EshSystemStatus.unknown;
    return ageSeconds < eshHeartbeatLifetime.inSeconds
        ? EshSystemStatus.online
        : EshSystemStatus.offline;
  }

  bool _isFreshEpochSeconds(int? sampledAt, DateTime now) {
    if (sampledAt == null) return false;
    final ageSeconds = now.millisecondsSinceEpoch ~/ 1000 - sampledAt;
    return ageSeconds >= 0 && ageSeconds < eshHeartbeatLifetime.inSeconds;
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
      _cancelFreshnessExpiry();
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
    await _slaveAvailabilitySubscription?.cancel();
    _dataSubscription = null;
    _connectionSubscription = null;
    _deviceDataSubscription = null;
    _slaveAvailabilitySubscription = null;
  }

  void _cancelPendingTimers() {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    _commandGenerations.clear();
  }

  void _cancelFreshnessExpiry() {
    _freshnessExpiryTimer?.cancel();
    _freshnessExpiryTimer = null;
    _freshnessGeneration++;
  }

  @override
  Future<void> close() async {
    await _cancelSubscriptions();
    _cancelPendingTimers();
    _cancelFreshnessExpiry();
    return super.close();
  }
}
