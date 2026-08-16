import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

enum EshSystemStatus { unknown, online, offline }

const _slaveOwnedRooms = {'lorong', 'kamar_1', 'kamar_2', 'dapur'};
const _unchangedSlaveOnline = Object();

abstract class MonitoringState {}

class MonitoringInitial extends MonitoringState {}

class MonitoringLoading extends MonitoringState {}

class MonitoringError extends MonitoringState {
  final String message;

  MonitoringError(this.message);
}

class MonitoringLoaded extends MonitoringState {
  final McbDataCollection mcbData;
  final bool isConnected;
  final EshSystemStatus eshStatus;
  final bool isPowerSampleFresh;
  final bool isEnvironmentSampleFresh;
  final bool? slaveOnline;
  final RoomDeviceCollection deviceData;
  final Map<DeviceAddress, RoomDeviceValue> desiredDevices;
  final Set<DeviceAddress> pendingDevices;
  final Map<DeviceAddress, String> commandErrors;

  MonitoringLoaded({
    required this.mcbData,
    required this.isConnected,
    this.eshStatus = EshSystemStatus.unknown,
    this.isPowerSampleFresh = false,
    this.isEnvironmentSampleFresh = false,
    this.slaveOnline,
    RoomDeviceCollection? deviceData,
    Map<DeviceAddress, RoomDeviceValue>? desiredDevices,
    Set<DeviceAddress>? pendingDevices,
    Map<DeviceAddress, String>? commandErrors,
  }) : deviceData = deviceData ?? RoomDeviceCollection.empty(),
       desiredDevices = Map<DeviceAddress, RoomDeviceValue>.unmodifiable(
         desiredDevices ?? const {},
       ),
       pendingDevices = Set<DeviceAddress>.unmodifiable(
         pendingDevices ?? const {},
       ),
       commandErrors = Map<DeviceAddress, String>.unmodifiable(
         commandErrors ?? const {},
       );

  bool get canControl => isConnected && eshStatus == EshSystemStatus.online;

  bool canControlDevice(DeviceAddress address) {
    return canControl &&
        (!_slaveOwnedRooms.contains(address.roomKey) || slaveOnline == true);
  }

  bool canShowDeviceState(DeviceAddress address) {
    return !_slaveOwnedRooms.contains(address.roomKey) || slaveOnline == true;
  }

  bool get isEshStatusStale => !isConnected;

  bool get canShowPowerData =>
      canControl && mcbData.mcb1.connected && isPowerSampleFresh;

  bool get canShowEnvironmentData =>
      canControl && mcbData.sensorData.connected && isEnvironmentSampleFresh;

  String? get controlDisabledReason {
    if (!isConnected) return 'Firebase terputus. Perintah tidak dikirim';
    if (eshStatus == EshSystemStatus.offline) {
      return 'Sistem ESH offline. Perintah tidak dikirim';
    }
    if (eshStatus == EshSystemStatus.unknown) {
      return 'Status ESH belum tersedia. Perintah tidak dikirim';
    }
    return null;
  }

  String? controlDisabledReasonFor(DeviceAddress address) {
    if (!canControl) return controlDisabledReason;
    if (!_slaveOwnedRooms.contains(address.roomKey) || slaveOnline == true) {
      return null;
    }
    if (slaveOnline == null) {
      return 'Status Slave belum tersedia. Perintah tidak dikirim';
    }
    return 'Slave tidak tersedia. Perintah tidak dikirim';
  }

  MonitoringLoaded copyWith({
    McbDataCollection? mcbData,
    bool? isConnected,
    EshSystemStatus? eshStatus,
    bool? isPowerSampleFresh,
    bool? isEnvironmentSampleFresh,
    Object? slaveOnline = _unchangedSlaveOnline,
    RoomDeviceCollection? deviceData,
    Map<DeviceAddress, RoomDeviceValue>? desiredDevices,
    Set<DeviceAddress>? pendingDevices,
    Map<DeviceAddress, String>? commandErrors,
  }) {
    return MonitoringLoaded(
      mcbData: mcbData ?? this.mcbData,
      isConnected: isConnected ?? this.isConnected,
      eshStatus: eshStatus ?? this.eshStatus,
      isPowerSampleFresh: isPowerSampleFresh ?? this.isPowerSampleFresh,
      isEnvironmentSampleFresh:
          isEnvironmentSampleFresh ?? this.isEnvironmentSampleFresh,
      slaveOnline: identical(slaveOnline, _unchangedSlaveOnline)
          ? this.slaveOnline
          : slaveOnline as bool?,
      deviceData: deviceData ?? this.deviceData,
      desiredDevices: desiredDevices ?? this.desiredDevices,
      pendingDevices: pendingDevices ?? this.pendingDevices,
      commandErrors: commandErrors ?? this.commandErrors,
    );
  }
}
