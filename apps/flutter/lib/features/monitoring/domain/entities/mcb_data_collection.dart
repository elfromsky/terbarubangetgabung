import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

class McbDataCollection {
  final McbData mcb1;
  final SensorData sensorData;
  final int? heartbeatEpochSeconds;

  const McbDataCollection({
    required this.mcb1,
    this.sensorData = const SensorData(temperature: 0, humidity: 0),
    this.heartbeatEpochSeconds,
  });

  factory McbDataCollection.empty() {
    return McbDataCollection(
      mcb1: McbData.empty(),
      sensorData: SensorData.empty(),
      heartbeatEpochSeconds: null,
    );
  }

  McbDataCollection copyWith({
    McbData? mcb1,
    SensorData? sensorData,
    int? heartbeatEpochSeconds,
  }) {
    return McbDataCollection(
      mcb1: mcb1 ?? this.mcb1,
      sensorData: sensorData ?? this.sensorData,
      heartbeatEpochSeconds:
          heartbeatEpochSeconds ?? this.heartbeatEpochSeconds,
    );
  }

  double get totalCurrent => mcb1.current;
  double get totalPower => mcb1.power;
  double get totalEnergy => mcb1.energy;
}
