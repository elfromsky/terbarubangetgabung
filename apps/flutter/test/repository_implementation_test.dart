import 'dart:async';

import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/models/canonical_history_dto.dart';
import 'package:esh/features/history/data/repositories/history_repository_impl.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:esh/features/monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonitoringDataSource implements MonitoringDataSource {
  final monitoringController =
      StreamController<RealtimeMonitoringDto>.broadcast();
  final connectionController = StreamController<bool>.broadcast();
  final slaveOnlineController = StreamController<bool?>.broadcast();

  @override
  Stream<bool> getConnectionStatus() => connectionController.stream;

  @override
  Stream<RealtimeMonitoringDto> getMonitoringDataStream() =>
      monitoringController.stream;

  @override
  Stream<bool?> getSlaveOnlineStream() => slaveOnlineController.stream;

  Future<void> close() async {
    await monitoringController.close();
    await connectionController.close();
    await slaveOnlineController.close();
  }
}

class FakeRoomDeviceDataSource implements RoomDeviceDataSource {
  final roomController = StreamController<RoomDeviceCollectionDto>.broadcast();
  List<RoomDeviceCommandDto>? commands;

  @override
  Future<void> controlRoomDevices(List<RoomDeviceCommandDto> commands) async {
    this.commands = commands;
  }

  @override
  Stream<RoomDeviceCollectionDto> getRoomDevicesStream() =>
      roomController.stream;

  Future<void> close() => roomController.close();
}

class FakeHistoryDataSource implements HistoryDataSource {
  DateTime? startDate;
  DateTime? endDate;
  int? receivedLimit;
  List<CanonicalHistoryDto> data = const [];
  Map<String, dynamic>? savedSensorLog;

  @override
  Future<List<CanonicalHistoryDto>> getHistoricalData({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 1000,
  }) async {
    this.startDate = startDate;
    this.endDate = endDate;
    receivedLimit = limit;
    return data;
  }

  @override
  Future<void> saveSensorLog(Map<String, dynamic> data) async {
    savedSensorLog = data;
  }
}

void main() {
  test('monitoring repository delegates single command as DTO', () async {
    final monitoringDataSource = FakeMonitoringDataSource();
    final roomDeviceDataSource = FakeRoomDeviceDataSource();
    final repository = MonitoringRepositoryImpl(
      monitoringDataSource: monitoringDataSource,
      roomDeviceDataSource: roomDeviceDataSource,
    );

    await repository.controlRoomDevice('dapur', 'lampu', true, 75, true);

    expect(roomDeviceDataSource.commands, hasLength(1));
    final command = roomDeviceDataSource.commands!.single;
    expect(command.roomKey, 'dapur');
    expect(command.deviceKey, 'lampu');
    expect(command.isOn, isTrue);
    expect(command.brightness, 75);
    expect(command.supportsBrightness, isTrue);

    await monitoringDataSource.close();
    await roomDeviceDataSource.close();
  });

  test(
    'shared bedroom brightness writes both leaves and preserves each state',
    () async {
      final monitoringDataSource = FakeMonitoringDataSource();
      final roomDeviceDataSource = FakeRoomDeviceDataSource();
      final repository = MonitoringRepositoryImpl(
        monitoringDataSource: monitoringDataSource,
        roomDeviceDataSource: roomDeviceDataSource,
      );
      final roomSubscription = repository.getRoomDevicesStream().listen((_) {});
      addTearDown(roomSubscription.cancel);
      addTearDown(monitoringDataSource.close);
      addTearDown(roomDeviceDataSource.close);

      roomDeviceDataSource.roomController.add(
        const RoomDeviceCollectionDto(
          rawValue: {
            'kamar_1': {
              'tools': {
                'lampu': {'state': false, 'brightness': 20},
              },
            },
            'kamar_2': {
              'tools': {
                'lampu': {'state': true, 'brightness': 20},
              },
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await repository.controlRoomDevice('kamar_1', 'lampu', true, 60, true);

      expect(roomDeviceDataSource.commands, hasLength(2));
      final commands = {
        for (final command in roomDeviceDataSource.commands!)
          command.roomKey: command,
      };
      expect(commands['kamar_1']!.isOn, isTrue);
      expect(commands['kamar_1']!.brightness, 60);
      expect(commands['kamar_2']!.isOn, isTrue);
      expect(commands['kamar_2']!.brightness, 60);
    },
  );

  test(
    'shared bedroom brightness is rejected when pair state is unknown',
    () async {
      final monitoringDataSource = FakeMonitoringDataSource();
      final roomDeviceDataSource = FakeRoomDeviceDataSource();
      final repository = MonitoringRepositoryImpl(
        monitoringDataSource: monitoringDataSource,
        roomDeviceDataSource: roomDeviceDataSource,
      );

      expect(
        () => repository.controlRoomDevice('kamar_1', 'lampu', false, 35, true),
        throwsA(isA<StateError>()),
      );
      expect(roomDeviceDataSource.commands, isNull);

      await monitoringDataSource.close();
      await roomDeviceDataSource.close();
    },
  );

  test('shared bedroom state change keeps pair brightness atomic', () async {
    final monitoringDataSource = FakeMonitoringDataSource();
    final roomDeviceDataSource = FakeRoomDeviceDataSource();
    final repository = MonitoringRepositoryImpl(
      monitoringDataSource: monitoringDataSource,
      roomDeviceDataSource: roomDeviceDataSource,
    );
    final roomSubscription = repository.getRoomDevicesStream().listen((_) {});
    addTearDown(roomSubscription.cancel);
    addTearDown(monitoringDataSource.close);
    addTearDown(roomDeviceDataSource.close);
    roomDeviceDataSource.roomController.add(
      const RoomDeviceCollectionDto(
        rawValue: {
          'kamar_1': {
            'tools': {
              'lampu': {'state': true, 'brightness': 60},
            },
          },
          'kamar_2': {
            'tools': {
              'lampu': {'state': true, 'brightness': 60},
            },
          },
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await repository.controlRoomDevice('kamar_1', 'lampu', false, 60, true);

    expect(roomDeviceDataSource.commands, hasLength(2));
    final commands = {
      for (final command in roomDeviceDataSource.commands!)
        command.roomKey: command,
    };
    expect(commands['kamar_1']!.isOn, isFalse);
    expect(commands['kamar_1']!.brightness, 60);
    expect(commands['kamar_2']!.isOn, isTrue);
    expect(commands['kamar_2']!.brightness, 60);
  });

  test(
    'monitoring repository maps DTO stream and delegates other streams',
    () async {
      final monitoringDataSource = FakeMonitoringDataSource();
      final roomDeviceDataSource = FakeRoomDeviceDataSource();
      final repository = MonitoringRepositoryImpl(
        monitoringDataSource: monitoringDataSource,
        roomDeviceDataSource: roomDeviceDataSource,
      );
      const monitoringValue = RealtimeMonitoringDto(
        environment: {'temperature': '28.5', 'humidity': 60, 'connected': true},
        power: {
          'connected': true,
          'voltage': 220,
          'current': '1.5',
          'power': 330,
          'energy': '12.75',
        },
        unixTime: 2000000000,
        environmentSampledAtEpochSeconds: 1999999999,
        powerSampledAtEpochSeconds: 1999999998,
      );
      const roomDevicesValue = RoomDeviceCollectionDto(
        rawValue: {
          'dapur': {
            'source': 'slave',
            'tools': {
              'lampu': {'state': true, 'brightness': 75},
            },
          },
        },
      );
      const connectionValue = true;
      const slaveOnlineValue = false;
      final monitoringReceived = Completer<McbDataCollection>();
      final roomDevicesReceived = Completer<RoomDeviceCollection>();
      final connectionReceived = Completer<bool>();
      final slaveOnlineReceived = Completer<bool?>();
      final monitoringSubscription = repository
          .getMonitoringDataStream()
          .listen(monitoringReceived.complete);
      final roomDevicesSubscription = repository.getRoomDevicesStream().listen(
        roomDevicesReceived.complete,
      );
      final connectionSubscription = repository.getConnectionStatus().listen(
        connectionReceived.complete,
      );
      final slaveOnlineSubscription = repository.getSlaveOnlineStream().listen(
        slaveOnlineReceived.complete,
      );

      addTearDown(monitoringDataSource.close);
      addTearDown(roomDeviceDataSource.close);
      addTearDown(() async {
        await monitoringSubscription.cancel();
        await roomDevicesSubscription.cancel();
        await connectionSubscription.cancel();
        await slaveOnlineSubscription.cancel();
      });

      monitoringDataSource.monitoringController.add(monitoringValue);
      roomDeviceDataSource.roomController.add(roomDevicesValue);
      monitoringDataSource.connectionController.add(connectionValue);
      monitoringDataSource.slaveOnlineController.add(slaveOnlineValue);

      final monitoring = await monitoringReceived.future;
      expect(monitoring.mcb1.connected, isTrue);
      expect(monitoring.mcb1.voltage, 220);
      expect(monitoring.mcb1.current, 1.5);
      expect(monitoring.mcb1.power, 330);
      expect(monitoring.mcb1.energy, 12.75);
      expect(monitoring.sensorData.temperature, 28.5);
      expect(monitoring.sensorData.humidity, 60);
      expect(monitoring.sensorData.connected, isTrue);
      expect(monitoring.heartbeatEpochSeconds, 2000000000);
      expect(monitoring.sensorData.sampledAtEpochSeconds, 1999999999);
      expect(monitoring.mcb1.sampledAtEpochSeconds, 1999999998);
      final roomDevices = await roomDevicesReceived.future;
      expect(
        roomDevices.find(
          const DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu'),
        ),
        const RoomDeviceValue(isOn: true, brightness: 75),
      );
      expect(await connectionReceived.future, connectionValue);
      expect(await slaveOnlineReceived.future, slaveOnlineValue);
    },
  );

  test(
    'history repository maps DTO query result and delegates dates',
    () async {
      final dataSource = FakeHistoryDataSource()
        ..data = const [
          CanonicalHistoryDto(
            id: 'history-1',
            timestamp: 1000,
            power: {
              'connected': true,
              'voltage': '220',
              'current': 1.5,
              'power': '330',
              'energy': 4.25,
            },
            environment: {'temperature': '27.5', 'humidity': 60},
          ),
        ];
      final repository = HistoryRepositoryImpl(historyDataSource: dataSource);
      final startDate = DateTime(2026, 7, 1);
      final endDate = DateTime(2026, 7, 2);

      final history = await repository.getHistoricalData(
        startDate: startDate,
        endDate: endDate,
        limit: 200,
      );

      expect(dataSource.startDate, startDate);
      expect(dataSource.endDate, endDate);
      expect(dataSource.receivedLimit, 200);
      expect(history, hasLength(1));
      expect(history.single.id, 'history-1');
      expect(
        history.single.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(history.single.mcb1!.connected, isTrue);
      expect(history.single.mcb1!.voltage, 220);
      expect(history.single.mcb1!.current, 1.5);
      expect(history.single.mcb1!.power, 330);
      expect(history.single.mcb1!.energy, 4.25);
    expect(history.single.sensorData!.temperature, 27.5);
    expect(history.single.sensorData!.humidity, 60);
  });

  test(
    'history repository writes canonical sensorLogs with derived values',
    () async {
      final dataSource = FakeHistoryDataSource();
      const estimateEnergyCost = EstimateEnergyCostUseCase(ratePerKwh: 1000);
      const estimateEmission = EstimateEmissionUseCase(
        emissionFactorKgCo2PerKwh: 0.5,
      );
      final repository = HistoryRepositoryImpl(
        historyDataSource: dataSource,
        estimateEnergyCost: estimateEnergyCost,
        estimateEmission: estimateEmission,
      );
      const collection = McbDataCollection(
        mcb1: McbData(
          connected: true,
          voltage: 220,
          current: 1,
          power: 220,
          energy: 2,
        ),
      );

      await repository.saveSensorLog(collection);

      expect(dataSource.savedSensorLog, isNotNull);
      final power = dataSource.savedSensorLog!['power'] as Map<String, dynamic>;
      final derived = dataSource.savedSensorLog!['derived']
          as Map<String, dynamic>;
      expect(power['energy'], 2.0);
      expect(derived['estimatedCost'], 2000.0);
      expect(derived['estimatedEmission'], 1.0);
    },
  );
}
