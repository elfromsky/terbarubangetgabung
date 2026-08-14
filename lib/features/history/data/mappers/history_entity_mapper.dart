import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/models/canonical_history_dto.dart';
import 'package:esh/features/history/data/models/legacy_history_dto.dart';
import 'package:esh/features/history/domain/entities/historical_mcb_data.dart';
import 'package:esh/features/monitoring/data/datasources/firebase_value_parser.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:intl/intl.dart';

DateTime parseFirestoreTimestamp(dynamic timestamp) {
  if (timestamp == null) return DateTime.now();
  if (timestamp is Timestamp) return timestamp.toDate();
  if (timestamp is String) {
    try {
      if (timestamp.contains('T')) return DateTime.parse(timestamp);
      if (timestamp.contains(' at ')) {
        final parts = timestamp.split(' at ');
        if (parts.length == 2) {
          final datePart = parts[0];
          final timePart = parts[1].split(' ')[0];
          return DateFormat(
            'dd MMM yyyy HH:mm:ss',
          ).parse('$datePart $timePart');
        }
      }
      return DateTime.parse(timestamp);
    } catch (_) {
      return DateTime.now();
    }
  }
  if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime.now();
}

HistoricalMcbData mapCanonicalHistoryDtoToEntity(CanonicalHistoryDto dto) {
  final timestamp = parseFirestoreTimestamp(dto.timestamp);
  final derived = dto.derived ?? {};

  return HistoricalMcbData(
    id: dto.id,
    timestamp: timestamp,
    mcb1: McbData(
      connected: dto.power['connected'] == true,
      voltage: parseFirebaseDouble(dto.power['voltage']),
      current: parseFirebaseDouble(dto.power['current']),
      power: parseFirebaseDouble(dto.power['power']),
      energy: parseFirebaseDouble(dto.power['energy']),
      lastUpdate: timestamp.millisecondsSinceEpoch,
    ),
    sensorData: SensorData(
      temperature: parseFirebaseDouble(dto.environment['temperature']),
      humidity: parseFirebaseDouble(dto.environment['humidity']),
    ),
    estimatedCost: parseFirebaseDouble(derived['estimatedCost']),
    estimatedEmission: parseFirebaseDouble(derived['estimatedEmission']),
  );
}

HistoricalMcbData mapLegacyHistoryDtoToEntity(LegacyHistoryDto dto) {
  try {
    DateTime timestamp;
    if (dto.timestamp is String) {
      timestamp = DateTime.parse(dto.timestamp);
    } else if (dto.timestamp != null) {
      timestamp = (dto.timestamp as dynamic).toDate();
    } else {
      timestamp = DateTime.now();
    }

    McbData? mcb1;
    if (dto.mcb1 != null) {
      mcb1 = _mapLegacyMcbData(dto.mcb1 as Map<String, dynamic>);
    }

    SensorData? sensorData;
    if (dto.dht != null) {
      sensorData = _mapLegacySensorData(
        Map<String, dynamic>.from(dto.dht as Map),
      );
    }

    return HistoricalMcbData(
      id: dto.id,
      timestamp: timestamp,
      mcb1: mcb1,
      sensorData: sensorData,
    );
  } catch (_) {
    return HistoricalMcbData(id: dto.id, timestamp: DateTime.now());
  }
}

DateTime legacyHistoryDtoSortTimestamp(LegacyHistoryDto dto) {
  return mapLegacyHistoryDtoToEntity(dto).timestamp;
}

HistoricalMcbData createLegacyHistoricalMcbData(
  McbDataCollection collection,
  String id,
  DateTime timestamp,
) {
  return HistoricalMcbData(
    id: id,
    timestamp: timestamp,
    mcb1: collection.mcb1,
    sensorData: collection.sensorData,
  );
}

LegacyHistoryDto mapLegacyHistoricalEntityToDto(
  HistoricalMcbData entity, {
  required bool timestampAsIsoString,
}) {
  return LegacyHistoryDto(
    id: entity.id,
    timestamp: timestampAsIsoString
        ? entity.timestamp.toIso8601String()
        : entity.timestamp,
    mcb1: _mapMcbDataToMap(entity.mcb1),
    dht: entity.sensorData == null
        ? null
        : {
            'temperature': entity.sensorData!.temperature,
            'humidity': entity.sensorData!.humidity,
          },
  );
}

McbData _mapLegacyMcbData(Map<String, dynamic> data) {
  return McbData(
    connected: data['connected'] ?? false,
    voltage: parseFirebaseDouble(data['voltage']),
    current: parseFirebaseDouble(data['current']),
    power: parseFirebaseDouble(data['power']),
    energy: parseFirebaseDouble(data['energy']),
    lastUpdate: _parseLegacyInt(data['lastUpdate']),
  );
}

SensorData _mapLegacySensorData(Map<String, dynamic> data) {
  return SensorData(
    temperature: parseFirebaseDouble(
      data['temperature'] ?? data['temp'] ?? data['suhu'],
    ),
    humidity: parseFirebaseDouble(
      data['humidity'] ?? data['hum'] ?? data['kelembapan'],
    ),
    connected: data['connected'] == true,
  );
}

int _parseLegacyInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

Map<String, dynamic>? _mapMcbDataToMap(McbData? mcbData) {
  if (mcbData == null) return null;
  return {
    'connected': mcbData.connected,
    'voltage': mcbData.voltage,
    'current': mcbData.current,
    'power': mcbData.power,
    'energy': mcbData.energy,
    'lastUpdate': mcbData.lastUpdate,
  };
}

/// Maps a real-time monitoring collection into the canonical `sensorLogs`
/// write payload.
Map<String, dynamic> mapMcbDataCollectionToCanonicalHistoryMap({
  required McbDataCollection collection,
  required double estimatedCost,
  required double estimatedEmission,
  required DateTime timestamp,
}) {
  return {
    'timestamp': timestamp,
    'power': {
      'connected': collection.mcb1.connected,
      'voltage': collection.mcb1.voltage,
      'current': collection.mcb1.current,
      'power': collection.mcb1.power,
      'energy': collection.mcb1.energy,
      if (collection.mcb1.sampledAtEpochSeconds != null)
        'sampled_at': collection.mcb1.sampledAtEpochSeconds,
    },
    'environment': {
      'connected': collection.sensorData.connected,
      'temperature': collection.sensorData.temperature,
      'humidity': collection.sensorData.humidity,
      if (collection.sensorData.sampledAtEpochSeconds != null)
        'sampled_at': collection.sensorData.sampledAtEpochSeconds,
    },
    'derived': {
      'estimatedCost': estimatedCost,
      'estimatedEmission': estimatedEmission,
    },
  };
}
