import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class ControlRoomDeviceUseCase {
  final MonitoringRepository repository;

  ControlRoomDeviceUseCase({required this.repository});

  Future<void> call({
    required String roomKey,
    required String deviceKey,
    required bool isOn,
    required int brightness,
    required bool supportsBrightness,
  }) {
    return repository.controlRoomDevice(
      roomKey,
      deviceKey,
      isOn,
      brightness,
      supportsBrightness,
    );
  }
}
