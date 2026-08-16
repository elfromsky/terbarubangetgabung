import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esh/features/history/data/mappers/firestore_history_mapper.dart';
import 'package:esh/features/history/data/mappers/history_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/monitoring_entity_mapper.dart';
import 'package:esh/features/monitoring/data/mappers/realtime_monitoring_mapper.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #19 energy-unit contract.
///
/// PZEM004Tv30::energy() (mandulaj/PZEM-004T-v30@1.1.2) already returns kWh
/// (it divides the raw 1-Wh register by 1000). Master publishes that value
/// unchanged and Flutter consumes it as kWh. These tests pin that contract so
/// no second Wh→kWh conversion is ever introduced.

void main() {
  group('energy ingestion (wire kWh passes through unchanged)', () {
    McbDataCollection mapEnergy(double energy) {
      final dto = mapRealtimeMonitoringDataToDto({
        'environment': {
          'temperature': 28,
          'humidity': 60,
          'connected': true,
          'sampled_at': 2000000000,
        },
        'power': {
          'connected': true,
          'voltage': 220,
          'current': 1,
          'power': 220,
          'energy': energy,
          'sampled_at': 2000000000,
        },
      });
      return mapRealtimeMonitoringDtoToEntity(dto);
    }

    test('known kWh values pass through without any /1000 scaling', () {
      for (final energy in [0.0, 0.001, 1.0, 1.234, 9999.99]) {
        expect(mapEnergy(energy).mcb1.energy, energy);
        expect(mapEnergy(energy).totalEnergy, energy);
      }
    });

    test('1.234 kWh is not reduced to 0.001234 kWh', () {
      final result = mapEnergy(1.234);
      expect(result.mcb1.energy, 1.234);
      expect(result.mcb1.energy, isNot(closeTo(0.001234, 1e-9)));
    });
  });

  group('estimated cost (kWh x tariff)', () {
    const useCase = EstimateEnergyCostUseCase(ratePerKwh: 1440.70);

    test('known kWh values produce correct Rp figures', () {
      expect(useCase(energyKwh: 0), 0);
      expect(useCase(energyKwh: 1), closeTo(1440.70, 1e-9));
      expect(useCase(energyKwh: 2), closeTo(2881.40, 1e-9));
      expect(useCase(energyKwh: 1.5), closeTo(2161.05, 1e-9));
    });
  });

  group('estimated emission (kWh x factor)', () {
    const useCase = EstimateEmissionUseCase(emissionFactorKgCo2PerKwh: 0.85);

    test('known kWh values produce correct kgCO2 figures', () {
      expect(useCase(energyKwh: 0), 0);
      expect(useCase(energyKwh: 1), closeTo(0.85, 1e-9));
      expect(useCase(energyKwh: 2), closeTo(1.70, 1e-9));
    });
  });

  group('history serialization/deserialization (kWh stays kWh)', () {
    test('canonical sensorLogs write retains kWh without scaling', () {
      final collection = McbDataCollection(
        mcb1: const McbData(
          connected: true,
          voltage: 220,
          current: 1.5,
          power: 330,
          energy: 1.234,
        ),
        sensorData: const SensorData(temperature: 28, humidity: 60),
      );

      final map = mapMcbDataCollectionToCanonicalHistoryMap(
        collection: collection,
        estimatedCost: 1.234 * 1440.70,
        estimatedEmission: 1.234 * 0.85,
        timestamp: DateTime(2026, 7, 13),
      );

      expect((map['power'] as Map)['energy'], 1.234);
    });

    test('canonical sensorLogs read exposes kWh unchanged', () {
      final dto = mapFirestoreToCanonicalHistoryDto({
        'timestamp': Timestamp(1, 0),
        'power': {
          'connected': true,
          'voltage': 220,
          'current': 1.5,
          'power': 330,
          'energy': 1.234,
        },
        'environment': {'temperature': 27.5, 'humidity': 60},
      }, 'energy-kwh');
      final entity = mapCanonicalHistoryDtoToEntity(dto);

      expect(entity.mcb1!.energy, 1.234);
    });
  });
}
