import 'dart:async';

import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/history/domain/repositories/history_repository.dart';
import 'package:esh/features/history/domain/usecases/load_history_data_use_case.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';
import 'package:esh/features/monitoring/domain/usecases/control_room_device_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_connection_status_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/watch_room_devices_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHistoryRepository implements HistoryRepository {
  DateTime? startDate;
  DateTime? endDate;
  int? limit;

  @override
  Future<List<HistoricalMcbData>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    this.startDate = startDate;
    this.endDate = endDate;
    this.limit = limit;
    return const [];
  }
}

class FakeMonitoringRepository implements MonitoringRepository {
  final monitoringController = StreamController<McbDataCollection>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  final roomController = StreamController<RoomDeviceCollection>.broadcast();
  late final Stream<McbDataCollection> monitoringStream =
      monitoringController.stream;
  late final Stream<bool> connectionStream = connectionController.stream;
  late final Stream<RoomDeviceCollection> roomStream = roomController.stream;
  List<Object>? command;

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) async {
    command = [roomKey, deviceKey, isOn, brightness, supportsBrightness];
  }

  @override
  Stream<bool> getConnectionStatus() => connectionStream;

  @override
  Stream<McbDataCollection> getMonitoringDataStream() => monitoringStream;

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() => roomStream;

  Future<void> close() async {
    await monitoringController.close();
    await connectionController.close();
    await roomController.close();
  }
}

void main() {
  late FakeMonitoringRepository monitoringRepository;

  setUp(() {
    monitoringRepository = FakeMonitoringRepository();
  });

  tearDown(() => monitoringRepository.close());

  test('monitoring stream use cases return repository streams', () async {
    final telemetry = WatchMonitoringDataUseCase(
      repository: monitoringRepository,
    );
    final connection = WatchConnectionStatusUseCase(
      repository: monitoringRepository,
    );
    final rooms = WatchRoomDevicesUseCase(repository: monitoringRepository);

    expect(telemetry(), same(monitoringRepository.monitoringStream));
    expect(connection(), same(monitoringRepository.connectionStream));
    expect(rooms(), same(monitoringRepository.roomStream));
  });

  test('control room device use case forwards canonical parameters', () async {
    final useCase = ControlRoomDeviceUseCase(repository: monitoringRepository);

    await useCase(
      roomKey: 'dapur',
      deviceKey: 'lampu',
      isOn: true,
      brightness: 75,
      supportsBrightness: true,
    );

    expect(monitoringRepository.command, ['dapur', 'lampu', true, 75, true]);
  });

  test('load history use case forwards date range and limit', () async {
    final repository = FakeHistoryRepository();
    final useCase = LoadHistoryDataUseCase(repository: repository);
    final startDate = DateTime(2026, 7, 1);
    final endDate = DateTime(2026, 7, 2);

    final result = await useCase(
      startDate: startDate,
      endDate: endDate,
      limit: 200,
    );

    expect(result, isEmpty);
    expect(repository.startDate, startDate);
    expect(repository.endDate, endDate);
    expect(repository.limit, 200);
  });

  test('estimate energy cost use case applies configured rate', () {
    final useCase = EstimateEnergyCostUseCase(ratePerKwh: 1699.53);

    expect(useCase(energyKwh: 10), 16995.3);
  });

  test('estimate emission use case applies configured factor', () {
    final useCase = EstimateEmissionUseCase(emissionFactorKgCo2PerKwh: 0.85);

    expect(useCase(energyKwh: 10), 8.5);
  });
}
