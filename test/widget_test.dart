import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/models/device_config.dart';
import 'package:esh/screen/history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history date selector fits 320px at 2x text scale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var changeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: HistoryDateRangeSelector(
              dateRange: '01 September 2026  -  30 September 2026',
              onChange: () => changeCount++,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Change'), findsOneWidget);

    await tester.tap(find.text('Change'));
    expect(changeCount, 1);
  });

  test('Teras exposes Lampu with canonical key and hides Lampu 2', () {
    final teras = findRoomConfig('teras');

    expect(teras, isNotNull);
    expect(
      teras!.devices.map((device) => device.displayName),
      orderedEquals(['Lampu', 'Sanyo']),
    );
    expect(teras.devices.first.deviceKey, 'lampu');
    expect(teras.devices.first.supportsBrightness, isFalse);
  });

  test('Dapur exposes dimmable Lampu and hides Lampu 2', () {
    final dapur = findRoomConfig('dapur');

    expect(dapur, isNotNull);
    expect(
      dapur!.devices.map((device) => device.displayName),
      orderedEquals(['Lampu', 'Blower']),
    );
    expect(dapur.devices.first.deviceKey, 'lampu');
    expect(dapur.devices.first.supportsBrightness, isTrue);
  });

  test('control event keeps display labels separate from canonical keys', () {
    final event = ControlRoomDevice(
      roomName: 'Teras Depan',
      roomKey: 'teras',
      deviceName: 'Lampu Utama',
      deviceKey: 'lampu',
      isOn: true,
      brightness: 100,
      supportsBrightness: false,
    );

    expect(event.roomName, 'Teras Depan');
    expect(event.roomKey, 'teras');
    expect(event.deviceName, 'Lampu Utama');
    expect(event.deviceKey, 'lampu');
  });
}
