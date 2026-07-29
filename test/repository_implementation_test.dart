import 'dart:async';

import 'package:esh/features/history/data/datasources/firebase_history_data_source.dart';
import 'package:esh/features/history/data/models/canonical_history_dto.dart';
import 'package:esh/features/history/data/repositories/history_repository_impl.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/room_device_collection_dto.dart';
import 'package:esh/features/monitoring/data/repositories/monitoring_repository_impl.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMonitoringDataSource implements MonitoringDataSource {
  final monitoringController =
      StreamController<RealtimeMonitoringDto>.broadcast();
  final connectionController = StreamController<bool>.broadcast();

  @override
  Stream<bool> getConnectionStatus() => connectionController.stream;

  @override
  Stream<RealtimeMonitoringDto> getMonitoringDataStream() =>
      monitoringController.stream;

  Future<void> close() async {
    await monitoringController.close();
    await connectionController.close();
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
      final monitoringReceived = Completer<McbDataCollection>();
      final roomDevicesReceived = Completer<RoomDeviceCollection>();
      final connectionReceived = Completer<bool>();
      final monitoringSubscription = repository
          .getMonitoringDataStream()
          .listen(monitoringReceived.complete);
      final roomDevicesSubscription = repository.getRoomDevicesStream().listen(
        roomDevicesReceived.complete,
      );
      final connectionSubscription = repository.getConnectionStatus().listen(
        connectionReceived.complete,
      );

      addTearDown(monitoringDataSource.close);
      addTearDown(roomDeviceDataSource.close);
      addTearDown(() async {
        await monitoringSubscription.cancel();
        await roomDevicesSubscription.cancel();
        await connectionSubscription.cancel();
      });

      monitoringDataSource.monitoringController.add(monitoringValue);
      roomDeviceDataSource.roomController.add(roomDevicesValue);
      monitoringDataSource.connectionController.add(connectionValue);

      final monitoring = await monitoringReceived.future;
      expect(monitoring.mcb1.connected, isTrue);
      expect(monitoring.mcb1.voltage, 220);
      expect(monitoring.mcb1.current, 1.5);
      expect(monitoring.mcb1.power, 330);
      expect(monitoring.mcb1.energy, 12.75);
      expect(monitoring.sensorData.temperature, 28.5);
      expect(monitoring.sensorData.humidity, 60);
      expect(monitoring.sensorData.connected, isTrue);
      final roomDevices = await roomDevicesReceived.future;
      expect(
        roomDevices.find(
          const DeviceAddress(roomKey: 'dapur', deviceKey: 'lampu'),
        ),
        const RoomDeviceValue(isOn: true, brightness: 75),
      );
      expect(await connectionReceived.future, connectionValue);
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
    },
  );
}
