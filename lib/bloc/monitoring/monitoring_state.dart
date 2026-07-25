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
  final RoomDeviceCollection confirmedDeviceData;
  final Set<DeviceAddress> pendingDevices;
  final Map<DeviceAddress, String> commandErrors;

  MonitoringLoaded({
    required this.mcbData,
    required this.isConnected,
    RoomDeviceCollection? deviceData,
    RoomDeviceCollection? confirmedDeviceData,
    Set<DeviceAddress>? pendingDevices,
    Map<DeviceAddress, String>? commandErrors,
  }) : deviceData = deviceData ?? RoomDeviceCollection.empty(),
       confirmedDeviceData =
           confirmedDeviceData ?? RoomDeviceCollection.empty(),
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
    RoomDeviceCollection? confirmedDeviceData,
    Set<DeviceAddress>? pendingDevices,
    Map<DeviceAddress, String>? commandErrors,
  }) {
    return MonitoringLoaded(
      mcbData: mcbData ?? this.mcbData,
      isConnected: isConnected ?? this.isConnected,
      deviceData: deviceData ?? this.deviceData,
      confirmedDeviceData: confirmedDeviceData ?? this.confirmedDeviceData,
      pendingDevices: pendingDevices ?? this.pendingDevices,
      commandErrors: commandErrors ?? this.commandErrors,
    );
  }
}
