import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/sensor_data_dto.dart';
import 'package:firebase_database/firebase_database.dart';

abstract interface class MonitoringDataSource {
  Stream<RealtimeMonitoringDto> getMonitoringDataStream();
  Stream<bool> getConnectionStatus();
}

class FirebaseMonitoringDataSource implements MonitoringDataSource {
  final DatabaseReference database;

  FirebaseMonitoringDataSource({required this.database});

  @override
  Stream<RealtimeMonitoringDto> getMonitoringDataStream() {
    return database.child('device/sensorData').onValue.map((event) {
      return mapRealtimeMonitoringDataToDto(event.snapshot.value);
    });
  }

  Stream<SensorDataDto> getSensorDataStream() {
    return database.child('device/sensorData/environment').onValue.map((event) {
      return mapRealtimeSensorDataToDto(event.snapshot.value);
    });
  }

  @override
  Stream<bool> getConnectionStatus() {
    return database.child('.info/connected').onValue.map((event) {
      return event.snapshot.value == true;
    });
  }
}
