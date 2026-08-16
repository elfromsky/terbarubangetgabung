import 'package:esh/app/app_dependencies.dart';
import 'package:esh/bloc/history/history_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository implements MonitoringRepository, HistoryRepository {
  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {}

  @override
  Stream<bool> getConnectionStatus() => const Stream.empty();

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    return const [];
  }

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => const Stream.empty();

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() => const Stream.empty();

  @override
  Stream<bool?> getSlaveOnlineStream() => const Stream.empty();

  @override
  Future<void> saveSensorLog(McbDataCollection collection) async {}
}

void main() {
  test('default electricity tariff matches PRD', () {
    expect(AppDependencies.defaultElectricityRate, 1440.70);
  });

  test('dependencies provide repository contracts to both BLoCs', () async {
    final repository = FakeRepository();
    final dependencies = AppDependencies(
      monitoringRepository: repository,
      historyRepository: repository,
      estimateEnergyCost: const EstimateEnergyCostUseCase(
        ratePerKwh: AppDependencies.defaultElectricityRate,
      ),
      estimateEmission: const EstimateEmissionUseCase(
        emissionFactorKgCo2PerKwh: 0.85,
      ),
    );
    final monitoringBloc = dependencies.createMonitoringBloc();
    final historyBloc = dependencies.createHistoryBloc();

    expect(monitoringBloc, isA<MonitoringBloc>());
    expect(historyBloc, isA<HistoryBloc>());

    await monitoringBloc.close();
    await historyBloc.close();
  });
}
