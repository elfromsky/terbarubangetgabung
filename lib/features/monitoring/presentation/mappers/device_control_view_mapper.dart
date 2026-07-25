import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';

DeviceControlViewState mapDeviceControlViewState({
  required RoomDeviceCollection visibleDevices,
  required DeviceAddress address,
  required bool isPending,
  required String? errorMessage,
}) {
  final value = visibleDevices.find(address);
  final phase = errorMessage != null
      ? DeviceControlPhase.failed
      : isPending
      ? DeviceControlPhase.pending
      : value == null
      ? DeviceControlPhase.unknown
      : value.isOn
      ? DeviceControlPhase.on
      : DeviceControlPhase.off;

  return DeviceControlViewState(
    phase: phase,
    value: value,
    errorMessage: errorMessage,
    isPending: isPending,
  );
}
