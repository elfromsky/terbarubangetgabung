import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String relativePath) {
  return File(relativePath).readAsStringSync();
}

void main() {
  group('Clean Architecture boundary tahap 1', () {
    test('domain repository contracts avoid framework imports', () {
      const repositoryFiles = [
        'lib/features/monitoring/domain/repositories/monitoring_repository.dart',
        'lib/features/history/domain/repositories/history_repository.dart',
      ];
      const forbiddenImports = [
        'package:flutter/',
        'package:flutter_bloc/',
        'package:firebase_',
        'package:cloud_firestore/',
      ];

      for (final file in repositoryFiles) {
        final source = readProjectFile(file);
        for (final forbiddenImport in forbiddenImports) {
          expect(source, isNot(contains(forbiddenImport)), reason: file);
        }
      }
    });

    test('history state avoids importing BLoC implementation', () {
      final source = readProjectFile('lib/bloc/history/history_state.dart');

      expect(source, isNot(contains("import 'history_bloc.dart';")));
      expect(
        source,
        contains(
          'package:esh/features/history/presentation/models/history_chart_data.dart',
        ),
      );
    });

    test('history screen avoids concrete Firebase service', () {
      final source = readProjectFile('lib/screen/history.dart');

      expect(source, isNot(contains('services/firebase_service.dart')));
      expect(source, isNot(contains('FirebaseService(')));
      expect(source, isNot(contains('BlocProvider(')));
    });

    test('BLoCs depend on domain contracts instead of Firebase adapter', () {
      const blocFiles = [
        'lib/bloc/monitoring/monitoring_bloc.dart',
        'lib/bloc/history/history_bloc.dart',
      ];

      for (final file in blocFiles) {
        final source = readProjectFile(file);
        expect(
          source,
          isNot(contains('services/firebase_service.dart')),
          reason: file,
        );
      }
    });

    test('BLoCs depend on use cases instead of repository contracts', () {
      const blocFiles = [
        'lib/bloc/monitoring/monitoring_bloc.dart',
        'lib/bloc/history/history_bloc.dart',
      ];

      for (final file in blocFiles) {
        final source = readProjectFile(file);
        expect(source, isNot(contains('/domain/repositories/')), reason: file);
        expect(source, contains('/domain/usecases/'), reason: file);
      }
    });

    test('use cases avoid data, framework, DTO, and BLoC imports', () {
      const useCaseFiles = [
        'lib/features/monitoring/domain/usecases/watch_monitoring_data_use_case.dart',
        'lib/features/monitoring/domain/usecases/watch_connection_status_use_case.dart',
        'lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart',
        'lib/features/monitoring/domain/usecases/watch_slave_availability_use_case.dart',
        'lib/features/monitoring/domain/usecases/control_room_device_use_case.dart',
        'lib/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart',
        'lib/features/monitoring/domain/usecases/estimate_emission_use_case.dart',
        'lib/features/history/domain/usecases/load_history_data_use_case.dart',
      ];
      const forbiddenTokens = [
        '/data/',
        'package:flutter',
        'package:firebase_',
        'package:cloud_firestore/',
        'flutter_bloc',
        'Dto',
      ];

      for (final file in useCaseFiles) {
        final source = readProjectFile(file);
        for (final token in forbiddenTokens) {
          expect(source, isNot(contains(token)), reason: file);
        }
      }
    });

    test('history BLoC imports presentation chart models', () {
      final source = readProjectFile('lib/bloc/history/history_bloc.dart');

      expect(
        source,
        contains('features/history/presentation/models/chart_point.dart'),
      );
      expect(
        source,
        contains(
          'features/history/presentation/models/history_chart_data.dart',
        ),
      );
      expect(source, isNot(contains('class HistoryChartData')));
      expect(source, isNot(contains('class ChartPoint')));
    });

    test('legacy FirebaseService file is removed', () {
      expect(File('lib/services/firebase_service.dart').existsSync(), isFalse);
    });

    test('legacy mixed model file is removed', () {
      expect(File('lib/models/model.dart').existsSync(), isFalse);
    });

    test('domain entities avoid data and framework types', () {
      const entityFiles = [
        'lib/features/monitoring/domain/entities/sensor_data.dart',
        'lib/features/monitoring/domain/entities/mcb_data.dart',
        'lib/features/monitoring/domain/entities/mcb_data_collection.dart',
        'lib/features/history/domain/entities/historical_mcb_data.dart',
      ];
      const forbiddenTokens = [
        'Map<',
        'dynamic',
        'fromMap',
        'toMap',
        'fromFirestore',
        'toFirestore',
        'package:firebase_',
        'package:cloud_firestore/',
        'package:flutter/',
        '/data/',
      ];

      for (final file in entityFiles) {
        final source = readProjectFile(file);
        for (final forbiddenToken in forbiddenTokens) {
          expect(source, isNot(contains(forbiddenToken)), reason: file);
        }
      }
    });

    test('repository implementations avoid Firebase SDK imports', () {
      const repositoryFiles = [
        'lib/features/monitoring/data/repositories/monitoring_repository_impl.dart',
        'lib/features/history/data/repositories/history_repository_impl.dart',
      ];

      for (final file in repositoryFiles) {
        final source = readProjectFile(file);
        expect(
          source,
          isNot(contains('package:firebase_database/')),
          reason: file,
        );
        expect(
          source,
          isNot(contains('package:cloud_firestore/')),
          reason: file,
        );
      }
    });

    test('Firebase data SDK imports stay in approved layers', () {
      final firebaseDataImport = RegExp(
        r'''^\s*import\s+['"]package:(?:firebase_database|cloud_firestore)/''',
        multiLine: true,
      );
      final violations = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final path = entity.path.replaceAll('\\', '/');
        final isAllowed =
            path.startsWith('lib/app/') ||
            path == 'lib/firebase_options.dart' ||
            path.contains('/data/datasources/') ||
            path.contains('/data/mappers/');

        if (!isAllowed &&
            firebaseDataImport.hasMatch(entity.readAsStringSync())) {
          violations.add(path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Firebase data SDK imports are allowed only in lib/app/, lib/firebase_options.dart, and data/datasources paths.',
      );
    });

    test('data source interfaces return DTOs', () {
      final monitoringSource = readProjectFile(
        'lib/features/monitoring/data/datasources/firebase_monitoring_data_source.dart',
      );
      final historySource = readProjectFile(
        'lib/features/history/data/datasources/firebase_history_data_source.dart',
      );

      expect(
        monitoringSource,
        contains('Stream<RealtimeMonitoringDto> getMonitoringDataStream();'),
      );
      expect(
        monitoringSource,
        contains('Stream<SensorDataDto> getSensorDataStream()'),
      );
      expect(
        monitoringSource,
        contains('Stream<bool?> getSlaveOnlineStream();'),
      );
      expect(monitoringSource, isNot(contains('getRawDatabaseStream')));
      expect(monitoringSource, isNot(contains('Stream<Map<String, dynamic>>')));
      expect(historySource, contains('Future<List<CanonicalHistoryDto>>'));
    });

    test('repository contracts expose entities and avoid DTOs', () {
      const repositoryFiles = [
        'lib/features/monitoring/domain/repositories/monitoring_repository.dart',
        'lib/features/history/domain/repositories/history_repository.dart',
      ];

      for (final file in repositoryFiles) {
        final source = readProjectFile(file);
        expect(source, isNot(contains('Dto')), reason: file);
        expect(source, contains('/domain/entities/'), reason: file);
      }
    });

    test('DTOs avoid framework, domain, repository, and Firebase imports', () {
      const dtoFiles = [
        'lib/features/monitoring/data/models/realtime_monitoring_dto.dart',
        'lib/features/monitoring/data/models/sensor_data_dto.dart',
        'lib/features/history/data/models/canonical_history_dto.dart',
        'lib/features/history/data/models/legacy_history_dto.dart',
      ];
      const forbiddenImports = [
        'package:flutter',
        'package:flutter_bloc',
        '/domain/entities/',
        '/domain/repositories/',
        'package:firebase_',
        'package:cloud_firestore/',
      ];

      for (final file in dtoFiles) {
        final source = readProjectFile(file);
        for (final forbiddenImport in forbiddenImports) {
          expect(source, isNot(contains(forbiddenImport)), reason: file);
        }
      }
    });

    test('repository implementations map DTOs to entities', () {
      final monitoringRepository = readProjectFile(
        'lib/features/monitoring/data/repositories/monitoring_repository_impl.dart',
      );
      final historyRepository = readProjectFile(
        'lib/features/history/data/repositories/history_repository_impl.dart',
      );

      expect(
        monitoringRepository,
        contains('mapRealtimeMonitoringDtoToEntity'),
      );
      expect(historyRepository, contains('mapCanonicalHistoryDtoToEntity'));
    });

    test('monitoring BLoC room state boundary is typed', () {
      const files = [
        'lib/bloc/monitoring/monitoring_event.dart',
        'lib/bloc/monitoring/monitoring_state.dart',
        'lib/bloc/monitoring/monitoring_bloc.dart',
      ];
      const forbiddenTokens = [
        'Map<String, dynamic>',
        "['rooms']",
        "['state']",
        "['brightness']",
        ".split('/')",
        '_deviceNode',
        '_setDeviceNode',
        '_deepCopyMap',
      ];

      for (final file in files) {
        final source = readProjectFile(file);
        expect(source, contains('DeviceAddress'), reason: file);
        if (file.endsWith('monitoring_bloc.dart')) {
          expect(source, contains('DeviceStateUpdated'), reason: file);
        } else {
          expect(source, contains('RoomDeviceCollection'), reason: file);
        }
        for (final forbiddenToken in forbiddenTokens) {
          expect(source, isNot(contains(forbiddenToken)), reason: file);
        }
      }
    });

    test('device presentation mapper avoids data and Firebase imports', () {
      const files = [
        'lib/features/monitoring/presentation/models/device_control_view_state.dart',
        'lib/features/monitoring/presentation/mappers/device_control_view_mapper.dart',
      ];
      const forbiddenTokens = [
        '/data/',
        'package:flutter',
        'package:flutter_bloc',
        'package:firebase_',
        'package:cloud_firestore/',
      ];

      for (final file in files) {
        final source = readProjectFile(file);
        for (final token in forbiddenTokens) {
          expect(source, isNot(contains(token)), reason: file);
        }
      }
    });

    test('raw room maps stay inside data DTO and mapper files', () {
      const typedConsumerFiles = [
        'lib/features/monitoring/domain/repositories/monitoring_repository.dart',
        'lib/features/monitoring/domain/usecases/watch_room_devices_use_case.dart',
        'lib/bloc/monitoring/monitoring_event.dart',
        'lib/bloc/monitoring/monitoring_state.dart',
        'lib/bloc/monitoring/monitoring_bloc.dart',
        'lib/screen/monitoring.dart',
        'lib/screen/control.dart',
      ];
      const forbiddenTokens = [
        'Map<String, dynamic>',
        'Map<dynamic, dynamic>',
        "['rooms']",
        "['state']",
        "['brightness']",
        '.split(\'/\')',
      ];

      for (final file in typedConsumerFiles) {
        final source = readProjectFile(file);
        for (final token in forbiddenTokens) {
          expect(
            source,
            isNot(contains(token)),
            reason: '$file contains $token',
          );
        }
      }
    });

    test('room mapper owns Firebase device node keys', () {
      final mapper = readProjectFile(
        'lib/features/monitoring/data/mappers/room_device_mapper.dart',
      );
      final dataSource = readProjectFile(
        'lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart',
      );

      expect(mapper, contains("rawValue['state']"));
      expect(mapper, contains("rawValue['brightness']"));
      expect(mapper, contains("roomValue['tools']"));
      expect(dataSource, isNot(contains("['state']")));
      expect(dataSource, isNot(contains("['brightness']")));
      expect(dataSource, contains("child('rooms')"));
    });

    test('room data source and repository use DTO/entity boundary', () {
      final dataSource = readProjectFile(
        'lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart',
      );
      final repository = readProjectFile(
        'lib/features/monitoring/data/repositories/monitoring_repository_impl.dart',
      );

      expect(dataSource, contains('Stream<RoomDeviceCollectionDto>'));
      expect(repository, contains('mapRoomDeviceCollectionDtoToEntity'));
      expect(repository, contains('Stream<RoomDeviceCollection>'));
      expect(repository, isNot(contains('Stream<Map<String, dynamic>>')));
    });

    test('presentation files avoid data and Firebase imports', () {
      const forbiddenImports = [
        '/data/',
        'package:firebase_',
        'package:cloud_firestore/',
      ];

      for (final entity in Directory(
        'lib/features/monitoring/presentation',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        final source = entity.readAsStringSync();
        for (final forbiddenImport in forbiddenImports) {
          expect(source, isNot(contains(forbiddenImport)), reason: path);
        }
      }

      for (final file in [
        'lib/screen/monitoring.dart',
        'lib/screen/control.dart',
      ]) {
        final source = readProjectFile(file);
        for (final forbiddenImport in forbiddenImports) {
          expect(source, isNot(contains(forbiddenImport)), reason: file);
        }
      }
    });

    test('new domain entities avoid framework and data imports', () {
      const entityFiles = [
        'lib/features/monitoring/domain/entities/room_device_state.dart',
        'lib/features/monitoring/domain/entities/room_device_collection.dart',
      ];
      const forbiddenImports = [
        'package:flutter',
        'package:flutter_bloc',
        'package:firebase_',
        'package:cloud_firestore/',
        '/data/',
      ];

      for (final file in entityFiles) {
        final source = readProjectFile(file);
        for (final forbiddenImport in forbiddenImports) {
          expect(source, isNot(contains(forbiddenImport)), reason: file);
        }
      }
    });
  });
}
