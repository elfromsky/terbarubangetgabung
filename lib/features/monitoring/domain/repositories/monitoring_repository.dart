import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';

abstract interface class MonitoringRepository {
  Stream<McbDataCollection> getMonitoringDataStream();
  Stream<RoomDeviceCollection> getRoomDevicesStream();
  Stream<bool> getConnectionStatus();
  Future<void> controlRoomDevice(
    String roomKey,
    String deviceKey,
    bool isOn,
    int brightness,
    bool supportsBrightness,
  );
}
