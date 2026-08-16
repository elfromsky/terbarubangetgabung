import 'package:esh/features/monitoring/data/models/realtime_monitoring_dto.dart';
import 'package:esh/features/monitoring/data/models/sensor_data_dto.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';

McbDataCollection mapRealtimeMonitoringDtoToEntity(RealtimeMonitoringDto dto) {
  final voltage = _parseFiniteDouble(dto.power['voltage']);
  final current = _parseFiniteDouble(dto.power['current']);
  final power = _parseFiniteDouble(dto.power['power']);
  final energy = _parseFiniteDouble(dto.power['energy']);
  final temperature = _parseFiniteDouble(dto.environment['temperature']);
  final humidity = _parseFiniteDouble(dto.environment['humidity']);
  final powerValuesValid =
      _isInRange(voltage, 80, 260) &&
      _isInRange(current, 0, 100) &&
      _isInRange(power, 0, 23000) &&
      _isInRange(energy, 0, 9999.99);
  final environmentValuesValid =
      _isInRange(temperature, -40, 125) && _isInRange(humidity, 0, 100);
  final powerConnected =
      dto.power['connected'] == true &&
      dto.powerSampledAtEpochSeconds != null &&
      powerValuesValid;
  final environmentConnected =
      dto.environment['connected'] == true &&
      dto.environmentSampledAtEpochSeconds != null &&
      environmentValuesValid;

  return McbDataCollection(
    heartbeatEpochSeconds: dto.unixTime,
    mcb1: McbData(
      connected: powerConnected,
      voltage: voltage ?? 0,
      current: current ?? 0,
      power: power ?? 0,
      energy: energy ?? 0,
      sampledAtEpochSeconds: dto.powerSampledAtEpochSeconds,
    ),
    sensorData: SensorData(
      temperature: environmentConnected ? temperature! : 0,
      humidity: environmentConnected ? humidity! : 0,
      connected: environmentConnected,
      sampledAtEpochSeconds: dto.environmentSampledAtEpochSeconds,
    ),
  );
}

double? _parseFiniteDouble(dynamic value) {
  final parsed = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text.trim()),
    _ => null,
  };
  return parsed != null && parsed.isFinite ? parsed : null;
}

bool _isInRange(double? value, double minimum, double maximum) {
  return value != null && value >= minimum && value <= maximum;
}

SensorData mapSensorDataDtoToEntity(SensorDataDto dto) {
  final temperature = _parseFiniteDouble(dto.temperature);
  final humidity = _parseFiniteDouble(dto.humidity);
  final connected =
      dto.connected &&
      _isInRange(temperature, -40, 125) &&
      _isInRange(humidity, 0, 100);
  return SensorData(
    temperature: connected ? temperature! : 0,
    humidity: connected ? humidity! : 0,
    connected: connected,
  );
}
