import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/bloc/history/history_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/repositories/history_repository_impl.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/history/domain/usecases/load_history_data_use_case.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:firebase_database/firebase_database.dart';

class AppDependencies {
  static const defaultElectricityRate = 1699.53;
  static const defaultEmissionFactor = 0.85;

  final MonitoringRepository monitoringRepository;
  final HistoryRepository historyRepository;
  final EstimateEnergyCostUseCase estimateEnergyCost;
  final EstimateEmissionUseCase estimateEmission;

  const AppDependencies({
    required this.monitoringRepository,
    required this.historyRepository,
    required this.estimateEnergyCost,
    required this.estimateEmission,
  });

  factory AppDependencies.firebase() {
    final database = FirebaseDatabase.instance.ref();
    final firestore = FirebaseFirestore.instance;
    final monitoringDataSource = FirebaseMonitoringDataSource(
      database: database,
    );
    final roomDeviceDataSource = FirebaseRoomDeviceDataSource(
      database: database,
    );
    final historyDataSource = FirebaseHistoryDataSource(firestore: firestore);

    return AppDependencies(
      monitoringRepository: MonitoringRepositoryImpl(
        monitoringDataSource: monitoringDataSource,
        roomDeviceDataSource: roomDeviceDataSource,
      ),
      historyRepository: HistoryRepositoryImpl(
        historyDataSource: historyDataSource,
      ),
      estimateEnergyCost: const EstimateEnergyCostUseCase(
        ratePerKwh: defaultElectricityRate,
      ),
      estimateEmission: const EstimateEmissionUseCase(
        emissionFactorKgCo2PerKwh: defaultEmissionFactor,
      ),
    );
  }

  MonitoringBloc createMonitoringBloc() {
    return MonitoringBloc(
      watchMonitoringData: WatchMonitoringDataUseCase(
        repository: monitoringRepository,
      ),
      watchConnectionStatus: WatchConnectionStatusUseCase(
        repository: monitoringRepository,
      ),
      watchRoomDevices: WatchRoomDevicesUseCase(
        repository: monitoringRepository,
      ),
      controlRoomDevice: ControlRoomDeviceUseCase(
        repository: monitoringRepository,
      ),
    );
  }

  HistoryBloc createHistoryBloc() {
    return HistoryBloc(
      loadHistoryData: LoadHistoryDataUseCase(repository: historyRepository),
    );
  }
}
