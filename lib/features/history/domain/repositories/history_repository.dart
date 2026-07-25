import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';

abstract interface class HistoryRepository {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });
}
