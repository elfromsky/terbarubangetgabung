import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';

abstract interface class HistoryRepository {
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  });

  /// Persist a canonical `sensorLogs` record derived from [collection].
  /// The implementation computes estimated cost and emission internally.
  Future<void> saveSensorLog(McbDataCollection collection);
}
