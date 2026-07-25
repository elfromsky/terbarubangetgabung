import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

class HistoricalMcbData {
  final String id;
  final DateTime timestamp;
  final McbData? mcb1;
  final SensorData? sensorData;

  const HistoricalMcbData({
    required this.id,
    required this.timestamp,
    this.mcb1,
    this.sensorData,
  });

  @override
  String toString() {
    return 'HistoricalMcbData(id: $id, timestamp: $timestamp)';
  }
}
