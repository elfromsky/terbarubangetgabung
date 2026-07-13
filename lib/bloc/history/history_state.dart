import 'package:esh/models/model.dart';

import 'history_bloc.dart';

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
