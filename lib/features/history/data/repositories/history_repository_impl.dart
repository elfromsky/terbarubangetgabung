import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryDataSource historyDataSource;

  HistoryRepositoryImpl({required this.historyDataSource});

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    final data = await historyDataSource.getHistoricalData(
      startDate: startDate,
      endDate: endDate,
      limit: limit,
    );
    return data.map(mapCanonicalHistoryDtoToEntity).toList();
  }
}
