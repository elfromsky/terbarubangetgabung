class McbData {
  final bool connected;
  final double voltage;
  final double current;
  final double power;
  final double energy;
  final int lastUpdate;
  final int? sampledAtEpochSeconds;

  const McbData({
    required this.connected,
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    this.lastUpdate = 0,
    this.sampledAtEpochSeconds,
  });

  factory McbData.empty() {
    return const McbData(
      connected: false,
      voltage: 0,
      current: 0,
      power: 0,
      energy: 0,
    );
  }

  McbData copyWith({
    bool? connected,
    double? voltage,
    double? current,
    double? power,
    double? energy,
    int? lastUpdate,
    int? sampledAtEpochSeconds,
  }) {
    return McbData(
      connected: connected ?? this.connected,
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      power: power ?? this.power,
      energy: energy ?? this.energy,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      sampledAtEpochSeconds:
          sampledAtEpochSeconds ?? this.sampledAtEpochSeconds,
    );
  }

  @override
  String toString() {
    return 'McbData(connected: $connected, voltage: $voltage, current: $current, power: $power, energy: $energy, lastUpdate: $lastUpdate, sampledAtEpochSeconds: $sampledAtEpochSeconds)';
  }
}
