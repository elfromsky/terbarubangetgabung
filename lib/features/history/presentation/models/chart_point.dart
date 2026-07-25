class ChartPoint {
  final double x;
  final double y;
  final String mcbName;
  final DateTime timestamp;

  ChartPoint({
    required this.x,
    required this.y,
    required this.mcbName,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'ChartPoint(x: $x, y: $y, mcbName: $mcbName, timestamp: $timestamp)';
  }
}
