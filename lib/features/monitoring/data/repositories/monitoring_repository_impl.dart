import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/room_device_mapper.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class MonitoringRepositoryImpl implements MonitoringRepository {
  final MonitoringDataSource monitoringDataSource;
  final RoomDeviceDataSource roomDeviceDataSource;
  RoomDeviceCollection _latestRoomDevices = RoomDeviceCollection.empty();

  MonitoringRepositoryImpl({
    required this.monitoringDataSource,
    required this.roomDeviceDataSource,
  });

  @override
  Stream<McbDataCollection> getMonitoringDataStream() {
    return monitoringDataSource.getMonitoringDataStream().map(
      mapRealtimeMonitoringDtoToEntity,
    );
  }

  @override
  Stream<RoomDeviceCollection> getRoomDevicesStream() {
    return roomDeviceDataSource.getRoomDevicesStream().map((dto) {
      final devices = mapRoomDeviceCollectionDtoToEntity(dto);
      _latestRoomDevices = devices;
      return devices;
    });
  }

  @override
  Stream<bool> getConnectionStatus() {
    return monitoringDataSource.getConnectionStatus();
  }

  @override
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  ) {
    var normalizedBrightness = brightness.clamp(0, 100).toInt();
    if (supportsBrightness && isOn && normalizedBrightness == 0) {
      normalizedBrightness = 1;
    }

    final commands = <RoomDeviceCommandDto>[
      RoomDeviceCommandDto(
        roomKey: roomKey,
        deviceKey: deviceKey,
        isOn: isOn,
        brightness: normalizedBrightness,
        supportsBrightness: supportsBrightness,
      ),
    ];

    final pairedRoomKey = _pairedBedroomRoomKey(
      roomKey,
      deviceKey,
      supportsBrightness,
    );
    if (pairedRoomKey != null) {
      final pairedValue = _latestRoomDevices.find(
        DeviceAddress(roomKey: pairedRoomKey, deviceKey: deviceKey),
      );
      if (pairedValue == null) {
        throw StateError('Status lampu pasangan belum tersedia');
      }
      commands.add(
        RoomDeviceCommandDto(
          roomKey: pairedRoomKey,
          deviceKey: deviceKey,
          isOn: pairedValue.isOn,
          brightness: normalizedBrightness,
          supportsBrightness: true,
        ),
      );
    }

    return roomDeviceDataSource.controlRoomDevices(commands);
  }
}

String? _pairedBedroomRoomKey(
  String roomKey,
  String deviceKey,
  bool supportsBrightness,
) {
  if (!supportsBrightness || deviceKey != 'lampu') return null;
  if (roomKey == 'kamar_1') return 'kamar_2';
  if (roomKey == 'kamar_2') return 'kamar_1';
  return null;
}
