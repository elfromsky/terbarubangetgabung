import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class WatchMonitoringDataUseCase {
  final MonitoringRepository repository;

  WatchMonitoringDataUseCase({required this.repository});

  Stream<McbDataCollection> call() {
    return repository.getMonitoringDataStream();
  }
}
