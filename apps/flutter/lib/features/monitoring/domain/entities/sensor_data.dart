class SensorData {
  final double temperature;
  final double humidity;
  final bool connected;
  final int? sampledAtEpochSeconds;

  const SensorData({
    required this.temperature,
    required this.humidity,
    this.connected = false,
    this.sampledAtEpochSeconds,
  });

  factory SensorData.empty() =>
      const SensorData(temperature: 0, humidity: 0, connected: false);

  // NWS/WPC Rothfusz regression (SR 90-23), exact Celsius-domain form.
  // Units, derivation, and limitations: docs/RESEARCH_PARAMETER_VALIDATION.md
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

  // PRD-defined thresholds; literature basis and limits:
  // docs/RESEARCH_PARAMETER_VALIDATION.md
  String get temperatureCategory {
    if (temperature <= 25.7) return 'Dingin';
    if (temperature <= 28.6) return 'Sejuk';
    if (temperature < 31.5) return 'Hangat';
    return 'Panas';
  }

  // PRD-defined thresholds; literature basis and limits:
  // docs/RESEARCH_PARAMETER_VALIDATION.md
  String get humidityCategory {
    if (humidity <= 60.25) return 'Kering';
    if (humidity < 86.62) return 'Normal';
    return 'Lembap';
  }
}
