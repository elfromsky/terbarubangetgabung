import 'package:esh/bloc/history/history_event.dart';
import 'package:esh/bloc/history/history_state.dart';
import 'package:esh/features/history/domain/usecases/load_history_data_use_case.dart';
import 'package:esh/features/history/presentation/models/chart_point.dart';
import 'package:esh/features/history/presentation/models/history_chart_data.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  final LoadHistoryDataUseCase loadHistoryData;
  int _requestSequence = 0;

  HistoryBloc({required this.loadHistoryData}) : super(HistoryInitial()) {
    on<LoadHistoryData>(_onLoadHistoryData);
    on<FilterHistoryData>(_onFilterHistoryData);
    on<RefreshHistoryData>(_onRefreshHistoryData);
  }

  Future<void> _onLoadHistoryData(
    LoadHistoryData event,
    Emitter<HistoryState> emit,
  ) async {
    final requestId = ++_requestSequence;
    emit(HistoryLoading());

    try {
      final rawData = await loadHistoryData(
        startDate: event.startDate,
        endDate: event.endDate,
        limit: event.limit ?? 2000,
      );
      if (requestId != _requestSequence) return;

      final historyData = rawData.cast<HistoricalMcbData>();

      if (historyData.isEmpty) {
        emit(HistoryEmpty());
        return;
      }

      final chartData = _processDataForCharts(historyData);

      emit(
        HistoryLoaded(
          historyData: historyData,
          chartData: chartData,
          startDate: event.startDate,
          endDate: event.endDate,
        ),
      );
    } catch (e) {
      if (requestId == _requestSequence) {
        emit(HistoryError('Failed to load history data: $e'));
      }
    }
  }

  Future<void> _onFilterHistoryData(
    FilterHistoryData event,
    Emitter<HistoryState> emit,
  ) async {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      emit(HistoryLoading());

      add(
        LoadHistoryData(
          startDate: event.startDate,
          endDate: event.endDate,
          limit: event.limit,
        ),
      );
    }
  }

  Future<void> _onRefreshHistoryData(
    RefreshHistoryData event,
    Emitter<HistoryState> emit,
  ) async {
    final currentState = state;
    if (currentState is HistoryLoaded) {
      add(
        LoadHistoryData(
          startDate: currentState.startDate,
          endDate: currentState.endDate,
        ),
      );
    } else {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      add(LoadHistoryData(startDate: yesterday, endDate: now));
    }
  }

  HistoryChartData _processDataForCharts(List<HistoricalMcbData> data) {
    final voltageData = <ChartPoint>[];
    final currentData = <ChartPoint>[];
    final powerData = <ChartPoint>[];
    final energyData = <ChartPoint>[];
    final temperatureData = <ChartPoint>[];
    final humidityData = <ChartPoint>[];

    // sort data by timestamp ascending
    final sortedData = List<HistoricalMcbData>.from(data);
    sortedData.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // save last values to apply tolerance filter
    double? lastV, lastI, lastP, lastE, lastT, lastH;

    // threshold values to ignore minor fluctuations
    const toleranceV = 0.5;
    const toleranceI = 0.02;
    const toleranceP = 2.0;
    const toleranceE = 0.005;
    const toleranceT = 0.3;
    const toleranceH = 1.0;

    for (int i = 0; i < sortedData.length; i++) {
      final record = sortedData[i];
      final time = record.timestamp.millisecondsSinceEpoch.toDouble();

      final isFirstOrLast = (i == 0 || i == sortedData.length - 1);

      if (record.mcb1 != null) {
        final v = record.mcb1!.voltage;
        final c = record.mcb1!.current;
        final p = record.mcb1!.power;
        final e = record.mcb1!.energy;

        if (isFirstOrLast || lastV == null || (v - lastV).abs() >= toleranceV) {
          voltageData.add(
            ChartPoint(
              x: time,
              y: v,
              mcbName: 'MCB',
              timestamp: record.timestamp,
            ),
          );
          lastV = v;
        }
        if (isFirstOrLast || lastI == null || (c - lastI).abs() >= toleranceI) {
          currentData.add(
            ChartPoint(
              x: time,
              y: c,
              mcbName: 'MCB',
              timestamp: record.timestamp,
            ),
          );
          lastI = c;
        }
        if (isFirstOrLast || lastP == null || (p - lastP).abs() >= toleranceP) {
          powerData.add(
            ChartPoint(
              x: time,
              y: p,
              mcbName: 'MCB',
              timestamp: record.timestamp,
            ),
          );
          lastP = p;
        }
        if (isFirstOrLast || lastE == null || (e - lastE).abs() >= toleranceE) {
          energyData.add(
            ChartPoint(
              x: time,
              y: e,
              mcbName: 'MCB',
              timestamp: record.timestamp,
            ),
          );
          lastE = e;
        }
      }

      if (record.sensorData != null) {
        final t = record.sensorData!.temperature;
        final h = record.sensorData!.humidity;

        if (isFirstOrLast || lastT == null || (t - lastT).abs() >= toleranceT) {
          temperatureData.add(
            ChartPoint(
              x: time,
              y: t,
              mcbName: 'DHT',
              timestamp: record.timestamp,
            ),
          );
          lastT = t;
        }
        if (isFirstOrLast || lastH == null || (h - lastH).abs() >= toleranceH) {
          humidityData.add(
            ChartPoint(
              x: time,
              y: h,
              mcbName: 'DHT',
              timestamp: record.timestamp,
            ),
          );
          lastH = h;
        }
      }
    }

    return HistoryChartData(
      voltageData: voltageData,
      currentData: currentData,
      powerData: powerData,
      energyData: energyData,
      temperatureData: temperatureData,
      humidityData: humidityData,
    );
  }
}
