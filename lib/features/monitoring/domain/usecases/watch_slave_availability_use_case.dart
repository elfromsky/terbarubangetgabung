import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchSlaveAvailabilityUseCase {
  final MonitoringRepository repository;

  WatchSlaveAvailabilityUseCase({required this.repository});

  Stream<bool?> call() {
    return repository.getSlaveOnlineStream();
  }
}
