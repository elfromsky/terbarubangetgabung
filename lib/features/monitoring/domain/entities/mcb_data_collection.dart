import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

class McbDataCollection {
  final McbData mcb1;
  final SensorData sensorData;

  const McbDataCollection({
    required this.mcb1,
    this.sensorData = const SensorData(temperature: 0, humidity: 0),
  });

  factory McbDataCollection.empty() {
    return McbDataCollection(
      mcb1: McbData.empty(),
      sensorData: SensorData.empty(),
    );
  }

  McbDataCollection copyWith({McbData? mcb1, SensorData? sensorData}) {
    return McbDataCollection(
      mcb1: mcb1 ?? this.mcb1,
      sensorData: sensorData ?? this.sensorData,
    );
  }

  double get totalCurrent => mcb1.current;
  double get totalPower => mcb1.power;
  double get totalEnergy => mcb1.energy;
}
