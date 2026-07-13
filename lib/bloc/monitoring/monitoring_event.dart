import 'package:esh/models/model.dart';

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
  final Map<String, dynamic> data;
  DeviceStateUpdated(this.data);
}

class ClearPendingCommand extends MonitoringEvent {
  final String pendingKey;
  ClearPendingCommand(this.pendingKey);
}

class MonitoringStreamFailed extends MonitoringEvent {
  final String message;
  MonitoringStreamFailed(this.message);
}

class CommandFailed extends MonitoringEvent {
  final String pendingKey;
  final String message;

  CommandFailed(this.pendingKey, this.message);
}
