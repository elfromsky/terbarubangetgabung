import 'package:esh/bloc/history/history_bloc.dart';
import 'package:esh/bloc/history/history_event.dart';
import 'package:esh/bloc/history/history_state.dart';
import 'package:esh/services/firebase_service.dart';
import 'package:esh/widgets/appbar.dart';
import 'package:esh/widgets/selector_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class History extends StatelessWidget {
  const History({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => HistoryBloc(firebaseService: FirebaseService()),
      child: const HistoryView(),
    );
  }
}

class HistoryDateRangeSelector extends StatelessWidget {
  final String dateRange;
  final VoidCallback onChange;

  const HistoryDateRangeSelector({
    super.key,
    required this.dateRange,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dateRange,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onChange,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B5D92),
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String _selectedCategory = 'Listrik';
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfNextDay = startOfDay.add(const Duration(days: 1));

    setState(() {
      _selectedDateRange = DateTimeRange(start: startOfDay, end: startOfDay);
    });

    context.read<HistoryBloc>().add(
      LoadHistoryData(startDate: startOfDay, endDate: startOfNextDay),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange =
        _selectedDateRange ??
        DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);

    final pickedRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2023),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Color(0xFF073246),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    if (pickedRange != null) {
      setState(() {
        _selectedDateRange = pickedRange;
      });

      final endDateExclusive = DateTime(
        pickedRange.end.year,
        pickedRange.end.month,
        pickedRange.end.day,
      ).add(const Duration(days: 1));

      context.read<HistoryBloc>().add(
        LoadHistoryData(
          startDate: pickedRange.start,
          endDate: endDateExclusive,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: _mainBg(),
        child: Column(
          children: [
            const Appbar(),
            PageSelector(
              onHistoryDropdownChanged: (value) {
                setState(() => _selectedCategory = value);
              },
            ),
            _buildDateRangeSelector(),
            Expanded(
              child: BlocBuilder<HistoryBloc, HistoryState>(
                builder: (context, state) {
                  if (state is HistoryLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  } else if (state is HistoryError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error: ${state.message}',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadInitialData,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  } else if (state is HistoryEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.data_usage_outlined,
                            color: Colors.white54,
                            size: 64,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No data available for selected time range',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    );
                  } else if (state is HistoryLoaded) {
                    return _buildChartsView(state);
                  }

                  return const Center(
                    child: Text(
                      'Select a time range to view data',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    final startStr = _selectedDateRange != null
        ? DateFormat('dd MMM yyyy').format(_selectedDateRange!.start)
        : 'Select Start Date';
    final endStr = _selectedDateRange != null
        ? DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)
        : 'Select End Date';

    return HistoryDateRangeSelector(
      dateRange: '$startStr  -  $endStr',
      onChange: _pickDateRange,
    );
  }

  Widget _buildChartsView(HistoryLoaded state) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<HistoryBloc>().add(RefreshHistoryData());
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildDataSummary(state),
            const SizedBox(height: 20),

            if (_selectedCategory == 'Listrik') ...[
              _buildChart(
                'Voltage (V)',
                state.chartData.voltageData,
                Colors.blue,
                'V',
                state.startDate,
                state.endDate,
              ),
              const SizedBox(height: 20),
              _buildChart(
                'Current (A)',
                state.chartData.currentData,
                Colors.orange,
                'A',
                state.startDate,
                state.endDate,
              ),
              const SizedBox(height: 20),
              _buildChart(
                'Power (W)',
                state.chartData.powerData,
                Colors.green,
                'W',
                state.startDate,
                state.endDate,
              ),
              const SizedBox(height: 20),
              _buildChart(
                'Energy (kWh)',
                state.chartData.energyData,
                Colors.purple,
                'kWh',
                state.startDate,
                state.endDate,
              ),
            ] else if (_selectedCategory == 'Suhu') ...[
              _buildChart(
                'Temperature (°C)',
                state.chartData.temperatureData,
                Colors.redAccent,
                '°C',
                state.startDate,
                state.endDate,
              ),
              const SizedBox(height: 20),
              _buildChart(
                'Humidity (%)',
                state.chartData.humidityData,
                Colors.cyan,
                '%',
                state.startDate,
                state.endDate,
              ),
            ],
            const SizedBox(height: 20),
            _buildLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSummary(HistoryLoaded state) {
    final totalRecords = state.historyData.length;
    final dateRange = totalRecords > 0
        ? '${DateFormat('MMM dd, HH:mm').format(state.historyData.first.timestamp)} - ${DateFormat('MMM dd, HH:mm').format(state.historyData.last.timestamp)}'
        : 'No data';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Data Summary',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Total Records: $totalRecords',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            'Time Range: $dateRange',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(
    String title,
    List<ChartPoint> data,
    Color baseColor,
    String unit,
    DateTime minDate,
    DateTime maxDate,
  ) {
    if (data.isEmpty) {
      return _buildEmptyChart(title);
    }

    // Group data by sensor source
    final sourceData = data.toList();

    // Sort by timestamp
    sourceData.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: minDate.millisecondsSinceEpoch.toDouble(),
                maxX: maxDate.millisecondsSinceEpoch.toDouble(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: Colors.white.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: _calculateTimeInterval(minDate, maxDate),
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max || value == meta.min) {
                          return const SizedBox.shrink();
                        }
                        final date = DateTime.fromMillisecondsSinceEpoch(
                          value.toInt(),
                        );
                        final rangeInDays = maxDate.difference(minDate).inDays;
                        String formatStr;
                        if (rangeInDays <= 1) {
                          formatStr = 'HH:mm';
                        } else if (rangeInDays <= 7) {
                          formatStr = 'dd MMM\nHH:mm';
                        } else {
                          formatStr = 'dd MMM yyyy';
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            DateFormat(formatStr).format(date),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                lineBarsData: [
                  if (sourceData.isNotEmpty)
                    _createLineChartBarData(
                      sourceData,
                      baseColor,
                      _selectedCategory == 'Listrik' ? 'MCB1' : 'DHT',
                    ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((touchedSpot) {
                        final point = data[touchedSpot.spotIndex];
                        final rangeInDays = maxDate.difference(minDate).inDays;

                        final formatStr = rangeInDays <= 1
                            ? 'HH:mm'
                            : 'dd MMM, HH:mm';

                        return LineTooltipItem(
                          '${point.mcbName}\n${point.y.toStringAsFixed(2)} $unit\n${DateFormat(formatStr).format(point.timestamp)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart(String title) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'No data available',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _createLineChartBarData(
    List<ChartPoint> data,
    Color color,
    String mcbName,
  ) {
    final isDataDense = data.length > 50;

    return LineChartBarData(
      spots: data.map((point) => FlSpot(point.x, point.y)).toList(),
      isCurved: false,
      color: color,
      barWidth: isDataDense ? 1.5 : 2.0,
      dotData: FlDotData(
        show: !isDataDense,
        getDotPainter: (spot, percent, barData, index) =>
            FlDotCirclePainter(radius: 2, color: color, strokeWidth: 0),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: isDataDense ? 0.05 : 0.1),
      ),
    );
  }

  double _calculateTimeInterval(DateTime minDate, DateTime maxDate) {
    final totalTimeSpan =
        maxDate.millisecondsSinceEpoch - minDate.millisecondsSinceEpoch;
    if (totalTimeSpan <= 0) return 60000.0;

    return (totalTimeSpan / 4).toDouble();
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [_LegendItem(color: Colors.blue, label: 'MCB1')],
      ),
    );
  }

  BoxDecoration _mainBg() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF073246), Color(0xFF0B5D92)],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
