import 'package:esh/features/history/presentation/models/chart_point.dart';

class HistoryChartData {
  final List<ChartPoint> voltageData;
  final List<ChartPoint> currentData;
  final List<ChartPoint> powerData;
  final List<ChartPoint> energyData;
  final List<ChartPoint> temperatureData;
  final List<ChartPoint> humidityData;
  final List<ChartPoint> estimatedCostData;
  final List<ChartPoint> estimatedEmissionData;

  HistoryChartData({
    required this.voltageData,
    required this.currentData,
    required this.powerData,
    required this.energyData,
    required this.temperatureData,
    required this.humidityData,
    this.estimatedCostData = const [],
    this.estimatedEmissionData = const [],
  });
}
