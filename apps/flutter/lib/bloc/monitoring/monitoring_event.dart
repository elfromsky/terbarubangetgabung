import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

abstract class MonitoringEvent {}

class StartMonitoring extends MonitoringEvent {}

class StopMonitoring extends MonitoringEvent {}

class DataUpdated extends MonitoringEvent {
  final McbDataCollection mcbData;

  DataUpdated(this.mcbData);
}

class ConnectionStatusChanged extends MonitoringEvent {
  final bool isConnected;

  ConnectionStatusChanged(this.isConnected);
}

class SlaveAvailabilityChanged extends MonitoringEvent {
  final bool? slaveOnline;

  SlaveAvailabilityChanged(this.slaveOnline);
}

class MonitoringFreshnessExpired extends MonitoringEvent {
  final int generation;

  MonitoringFreshnessExpired(this.generation);
}

class ControlRoomDevice extends MonitoringEvent {
  final String roomName;
  final String roomKey;
  final String deviceName;
  final String deviceKey;
  final bool isOn;
  final double brightness;
  final bool supportsBrightness;

  ControlRoomDevice({
    required this.roomName,
    required this.roomKey,
    required this.deviceName,
    required this.deviceKey,
    required this.isOn,
    required this.brightness,
    required this.supportsBrightness,
  });
}

class DeviceStateUpdated extends MonitoringEvent {
  final RoomDeviceCollection data;

  DeviceStateUpdated(this.data);
}

class ClearPendingCommand extends MonitoringEvent {
  final DeviceAddress address;
  final int generation;

  ClearPendingCommand(this.address, [this.generation = 0]);
}

class MonitoringStreamFailed extends MonitoringEvent {
  final String message;

  MonitoringStreamFailed(this.message);
}

class CommandFailed extends MonitoringEvent {
  final DeviceAddress address;
  final String message;
  final int generation;

  CommandFailed(this.address, this.message, [this.generation = 0]);
}
