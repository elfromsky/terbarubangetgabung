import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';

enum DeviceControlPhase { unknown, off, on, pending, failed }

class DeviceControlViewState {
  final DeviceControlPhase phase;
  final RoomDeviceValue? value;
  final String? errorMessage;
  final bool isPending;

  const DeviceControlViewState({
    required this.phase,
    required this.value,
    required this.errorMessage,
    this.isPending = false,
  });

  bool get hasKnownValue => value != null;

  bool get controlsEnabled =>
      value != null && !isPending && phase != DeviceControlPhase.pending;
}
