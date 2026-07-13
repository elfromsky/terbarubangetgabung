import 'package:esh/models/model.dart';

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
  final Map<String, dynamic> deviceData;
  final Map<String, dynamic> confirmedDeviceData;
  final Set<String> pendingDevices;
  final Map<String, String> commandErrors;

  MonitoringLoaded({
    required this.mcbData,
    required this.isConnected,
    this.deviceData = const {},
    this.confirmedDeviceData = const {},
    this.pendingDevices = const {},
    this.commandErrors = const {},
  });

  MonitoringLoaded copyWith({
    McbDataCollection? mcbData,
    bool? isConnected,
    Map<String, dynamic>? deviceData,
    Map<String, dynamic>? confirmedDeviceData,
    Set<String>? pendingDevices,
    Map<String, String>? commandErrors,
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
