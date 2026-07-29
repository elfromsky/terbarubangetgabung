import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

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
  final RoomDeviceCollection deviceData;
  final Map<DeviceAddress, RoomDeviceValue> desiredDevices;
  final Set<DeviceAddress> pendingDevices;
  final Map<DeviceAddress, String> commandErrors;

  MonitoringLoaded({
    required this.mcbData,
    required this.isConnected,
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

  MonitoringLoaded copyWith({
    McbDataCollection? mcbData,
    bool? isConnected,
    RoomDeviceCollection? deviceData,
    Map<DeviceAddress, RoomDeviceValue>? desiredDevices,
    Set<DeviceAddress>? pendingDevices,
    Map<DeviceAddress, String>? commandErrors,
  }) {
    return MonitoringLoaded(
      mcbData: mcbData ?? this.mcbData,
      isConnected: isConnected ?? this.isConnected,
      deviceData: deviceData ?? this.deviceData,
      desiredDevices: desiredDevices ?? this.desiredDevices,
      pendingDevices: pendingDevices ?? this.pendingDevices,
      commandErrors: commandErrors ?? this.commandErrors,
    );
  }
}
