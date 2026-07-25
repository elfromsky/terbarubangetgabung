import 'package:esh/features/history/presentation/models/chart_point.dart';

class HistoryChartData {
  final List<ChartPoint> voltageData;
  final List<ChartPoint> currentData;
  final List<ChartPoint> powerData;
  final List<ChartPoint> energyData;
  final List<ChartPoint> temperatureData;
  final List<ChartPoint> humidityData;

  HistoryChartData({
    required this.voltageData,
    required this.currentData,
    required this.powerData,
    required this.energyData,
    required this.temperatureData,
    required this.humidityData,
  });
}
