import 'package:esh/features/history/presentation/models/history_chart_data.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';

abstract class HistoryState {}

class HistoryInitial extends HistoryState {}

class HistoryLoading extends HistoryState {}

class HistoryLoaded extends HistoryState {
  final List<HistoricalMcbData> historyData;
  final HistoryChartData chartData;
  final DateTime startDate;
  final DateTime endDate;

  HistoryLoaded({
    required this.historyData,
    required this.chartData,
    required this.startDate,
    required this.endDate,
  });
}

class HistoryEmpty extends HistoryState {}

class HistoryError extends HistoryState {
  final String message;

  HistoryError(this.message);
}
