import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchConnectionStatusUseCase {
  final MonitoringRepository repository;

  WatchConnectionStatusUseCase({required this.repository});

  Stream<bool> call() {
    return repository.getConnectionStatus();
  }
}
