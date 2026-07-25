import 'package:esh/features/monitoring/data/datasources/firebase_monitoring_data_source.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_room_device_data_source.dart';
import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/room_device_mapper.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/repositories/monitoring_repository.dart';

class MonitoringRepositoryImpl implements MonitoringRepository {
  final MonitoringDataSource monitoringDataSource;
  final RoomDeviceDataSource roomDeviceDataSource;

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
    return roomDeviceDataSource.getRoomDevicesStream().map(
      mapRoomDeviceCollectionDtoToEntity,
    );
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
    return roomDeviceDataSource.controlRoomDevice(
      roomKey,
      deviceKey,
      isOn,
      brightness,
      supportsBrightness,
    );
  }
}
