import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';

class LoadHistoryDataUseCase {
  final HistoryRepository repository;

  LoadHistoryDataUseCase({required this.repository});

  Future<List<HistoricalMcbData>> call({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) {
    return repository.getHistoricalData(
      startDate: startDate,
      endDate: endDate,
      limit: limit,
    );
  }
}
