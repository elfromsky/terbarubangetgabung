import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final HistoryDataSource historyDataSource;
  final EstimateEnergyCostUseCase estimateEnergyCost;
  final EstimateEmissionUseCase estimateEmission;

  HistoryRepositoryImpl({
    required this.historyDataSource,
    EstimateEnergyCostUseCase? estimateEnergyCost,
    EstimateEmissionUseCase? estimateEmission,
  }) : estimateEnergyCost = estimateEnergyCost ??
            const EstimateEnergyCostUseCase(ratePerKwh: 1440.70),
       estimateEmission = estimateEmission ??
            const EstimateEmissionUseCase(emissionFactorKgCo2PerKwh: 0.85);

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

  @override
  Future<void> saveSensorLog(McbDataCollection collection) async {
    final now = DateTime.now();
    final estimatedCost = estimateEnergyCost(energyKwh: collection.totalEnergy);
    final estimatedEmission = estimateEmission(
      energyKwh: collection.totalEnergy,
    );
    final data = mapMcbDataCollectionToCanonicalHistoryMap(
      collection: collection,
      estimatedCost: estimatedCost,
      estimatedEmission: estimatedEmission,
      timestamp: now,
    );
    return historyDataSource.saveSensorLog(data);
  }
}
