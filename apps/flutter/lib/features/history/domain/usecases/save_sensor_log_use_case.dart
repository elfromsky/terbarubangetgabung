import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';

class SaveSensorLogUseCase {
  final HistoryRepository repository;

  const SaveSensorLogUseCase({required this.repository});

  Future<void> call(McbDataCollection collection) {
    return repository.saveSensorLog(collection);
  }
}
