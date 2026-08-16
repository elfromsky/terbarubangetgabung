import 'package:esh/auth/auth_gate_controller.dart';
import 'package:esh/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLoader {
  _FakeLoader(this._handler);

  final Future<Map<String, dynamic>?> Function(bool force) _handler;
  int retryCount = 0;

  Future<Map<String, dynamic>?> call({required bool forceClaimRefresh}) {
    if (forceClaimRefresh) {
      retryCount += 1;
    }
    return _handler(forceClaimRefresh);
  }
}

Widget _operationalApp() =>
    const MaterialApp(home: Scaffold(body: Text('OPERATIONAL_APP')));

void main() {
  testWidgets('unprovisioned shows enrollment and not the operational app', (
    WidgetTester tester,
  ) async {
    final loader = _FakeLoader((_) async => <String, dynamic>{});
    final controller = AuthGateController(loadClaims: loader.call);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FirebaseBootstrap(
        controller: controller,
        trustedAppBuilder: _operationalApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Perangkat belum terdaftar'), findsOneWidget);
    expect(find.text('OPERATIONAL_APP'), findsNothing);
  });

  testWidgets('unprovisioned shows the device UID', (
    WidgetTester tester,
  ) async {
    final loader = _FakeLoader((_) async => <String, dynamic>{});
    final controller = AuthGateController(
      loadClaims: loader.call,
      loadUid: () async => 'anonymous-uid-123',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(FirebaseBootstrap(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('ID perangkat:'), findsOneWidget);
    expect(find.text('anonymous-uid-123'), findsOneWidget);
  });

  testWidgets('error shows retry state and not the operational app', (
    WidgetTester tester,
  ) async {
    final loader = _FakeLoader((_) async => null);
    final controller = AuthGateController(loadClaims: loader.call);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FirebaseBootstrap(
        controller: controller,
        trustedAppBuilder: _operationalApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Firebase gagal diinisialisasi'), findsOneWidget);
    expect(find.text('OPERATIONAL_APP'), findsNothing);
  });

  testWidgets('tapping Coba lagi invokes the controller retry path', (
    WidgetTester tester,
  ) async {
    var owner = false;
    final loader = _FakeLoader(
      (_) async => owner ? {'owner': true} : <String, dynamic>{},
    );
    final controller = AuthGateController(loadClaims: loader.call);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FirebaseBootstrap(
        controller: controller,
        trustedAppBuilder: _operationalApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Perangkat belum terdaftar'), findsOneWidget);

    owner = true;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(loader.retryCount, 1);
    expect(find.text('OPERATIONAL_APP'), findsOneWidget);
  });

  testWidgets('trusted reaches the operational app builder', (
    WidgetTester tester,
  ) async {
    final loader = _FakeLoader((_) async => {'owner': true});
    final controller = AuthGateController(loadClaims: loader.call);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FirebaseBootstrap(
        controller: controller,
        trustedAppBuilder: _operationalApp,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OPERATIONAL_APP'), findsOneWidget);
  });
}
