import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

class HistoricalMcbData {
  final String id;
  final DateTime timestamp;
  final McbData? mcb1;
  final SensorData? sensorData;
  final double estimatedCost;
  final double estimatedEmission;

  const HistoricalMcbData({
    required this.id,
    required this.timestamp,
    this.mcb1,
    this.sensorData,
    this.estimatedCost = 0.0,
    this.estimatedEmission = 0.0,
  });

  HistoricalMcbData copyWith({
    String? id,
    DateTime? timestamp,
    McbData? mcb1,
    SensorData? sensorData,
    double? estimatedCost,
    double? estimatedEmission,
  }) {
    return HistoricalMcbData(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      mcb1: mcb1 ?? this.mcb1,
      sensorData: sensorData ?? this.sensorData,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      estimatedEmission: estimatedEmission ?? this.estimatedEmission,
    );
  }

  @override
  String toString() {
    return 'HistoricalMcbData(id: $id, timestamp: $timestamp)';
  }
}
