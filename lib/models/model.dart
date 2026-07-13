// File: lib/models/monitoring_model.dart
// Model terpadu untuk menghindari konflik type casting

/// Data dari sensor DHT (suhu & kelembapan)
class SensorData {
  final double temperature; // °C
  final double humidity; // %
  final bool connected;

  const SensorData({
    required this.temperature,
    required this.humidity,
    this.connected = false,
  });

  factory SensorData.empty() =>
      const SensorData(temperature: 0, humidity: 0, connected: false);

  factory SensorData.fromMap(Map<String, dynamic> map) {
    return SensorData(
      temperature: _parseDouble(
        map['temperature'] ?? map['temp'] ?? map['suhu'],
      ),
      humidity: _parseDouble(
        map['humidity'] ?? map['hum'] ?? map['kelembapan'],
      ),
      connected: map['connected'] == true,
    );
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  /// Heat Index (Indeks Panas) — Rothfusz simplified formula
  double get heatIndex {
    if (temperature < 27) return temperature;
    const c1 = -8.78469475556;
    const c2 = 1.61139411;
    const c3 = 2.33854883889;
    const c4 = -0.14611605;
    const c5 = -0.012308094;
    const c6 = -0.0164248277778;
    const c7 = 0.002211732;
    const c8 = 0.00072546;
    const c9 = -0.000003582;
    final t = temperature;
    final h = humidity;
    return c1 +
        c2 * t +
        c3 * h +
        c4 * t * h +
        c5 * t * t +
        c6 * h * h +
        c7 * t * t * h +
        c8 * t * h * h +
        c9 * t * t * h * h;
  }

  /// Tingkat kenyamanan berdasarkan suhu & kelembapan
  String get comfortLevel {
    if (temperature < 18) return 'Dingin';
    if (temperature > 30) return 'Panas';
    if (humidity < 30) return 'Kering';
    if (humidity > 70) return 'Lembap';
    return 'Nyaman';
  }
}

class McbData {
  final bool connected;
  final double voltage;
  final double current;
  final double power;
  final double energy;
  final int lastUpdate;

  const McbData({
    required this.connected,
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    this.lastUpdate = 0,
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

  factory McbData.fromMap(Map<String, dynamic> map) {
    return McbData(
      connected: map['connected'] ?? false,
      voltage: _parseDouble(map['voltage']),
      current: _parseDouble(map['current']),
      power: _parseDouble(map['power']),
      energy: _parseDouble(map['energy']),
      lastUpdate: _parseInt(map['lastUpdate']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'connected': connected,
      'voltage': voltage,
      'current': current,
      'power': power,
      'energy': energy,
      'lastUpdate': lastUpdate,
    };
  }

  McbData copyWith({
    bool? connected,
    double? voltage,
    double? current,
    double? power,
    double? energy,
    int? lastUpdate,
  }) {
    return McbData(
      connected: connected ?? this.connected,
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      power: power ?? this.power,
      energy: energy ?? this.energy,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  @override
  String toString() {
    return 'McbData(connected: $connected, voltage: $voltage, current: $current, power: $power, energy: $energy, lastUpdate: $lastUpdate)';
  }
}

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

  // Aggregate calculations
  double get totalCurrent => mcb1.current;
  double get totalPower => mcb1.power;
  double get totalEnergy => mcb1.energy;
}

// Model untuk data historis - HANYA SATU DEFINISI
class HistoricalMcbData {
  final String id;
  final DateTime timestamp;
  final McbData? mcb1;
  final SensorData? sensorData;

  const HistoricalMcbData({
    required this.id,
    required this.timestamp,
    this.mcb1,
    this.sensorData,
  });

  factory HistoricalMcbData.fromMcbCollection(
    McbDataCollection collection,
    String id,
  ) {
    return HistoricalMcbData(
      id: id,
      timestamp: DateTime.now(),
      mcb1: collection.mcb1,
      sensorData: collection.sensorData,
    );
  }

  factory HistoricalMcbData.fromFirestore(
    Map<String, dynamic> data,
    String id,
  ) {
    try {
      // Parse timestamp
      DateTime timestamp;
      if (data['timestamp'] is String) {
        timestamp = DateTime.parse(data['timestamp']);
      } else if (data['timestamp'] != null) {
        timestamp = (data['timestamp'] as dynamic).toDate();
      } else {
        timestamp = DateTime.now();
      }

      // Parse MCB data
      McbData? mcb1;

      if (data['mcb1'] != null) {
        mcb1 = McbData.fromMap(data['mcb1'] as Map<String, dynamic>);
      }

      // Parse Sensor data
      SensorData? sensorData;
      if (data['dht'] != null) {
        sensorData = SensorData.fromMap(
          Map<String, dynamic>.from(data['dht'] as Map),
        );
      }

      return HistoricalMcbData(
        id: id,
        timestamp: timestamp,
        mcb1: mcb1,
        sensorData: sensorData,
      );
    } catch (e) {
      return HistoricalMcbData(id: id, timestamp: DateTime.now());
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'mcb1': mcb1?.toMap(),
      if (sensorData != null)
        'dht': {
          'temperature': sensorData!.temperature,
          'humidity': sensorData!.humidity,
        },
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'timestamp': timestamp,
      'mcb1': mcb1?.toMap(),
      if (sensorData != null)
        'dht': {
          'temperature': sensorData!.temperature,
          'humidity': sensorData!.humidity,
        },
    };
  }

  @override
  String toString() {
    return 'HistoricalMcbData(id: $id, timestamp: $timestamp)';
  }
}
