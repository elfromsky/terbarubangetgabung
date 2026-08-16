import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchRoomDevicesUseCase {
  final MonitoringRepository repository;

  WatchRoomDevicesUseCase({required this.repository});

  Stream<RoomDeviceCollection> call() {
    return repository.getRoomDevicesStream();
  }
}
