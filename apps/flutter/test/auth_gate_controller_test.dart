import 'dart:async';

import 'package:esh/auth/auth_gate_controller.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _RecordedCall = ({bool forceClaimRefresh});

class _FakeLoader {
  _FakeLoader(this._handler);

  final Future<Map<String, dynamic>?> Function(bool force) _handler;
  final List<_RecordedCall> calls = [];

  Future<Map<String, dynamic>?> call({required bool forceClaimRefresh}) {
    calls.add((forceClaimRefresh: forceClaimRefresh));
    return _handler(forceClaimRefresh);
  }
}

void main() {
  group('initial status', () {
    test('starts in loading', () {
      final controller = AuthGateController(
        loadClaims: _FakeLoader((_) async => null).call,
      );
      expect(controller.status, AuthGateStatus.loading);
    });
  });

  group('bootstrap', () {
    test('valid owner: loading -> trusted, forceClaimRefresh false', () async {
      final loader = _FakeLoader((_) async => {'owner': true});
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();

      expect(controller.status, AuthGateStatus.trusted);
      expect(loader.calls, hasLength(1));
      expect(loader.calls.single.forceClaimRefresh, isFalse);
    });

    test('authenticated without owner: loading -> unprovisioned', () async {
      final loader = _FakeLoader((_) async => <String, dynamic>{});
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();

      expect(controller.status, AuthGateStatus.unprovisioned);
    });

    test('controller only (no owner): loading -> unprovisioned', () async {
      final loader = _FakeLoader((_) async => {'controller': true});
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();

      expect(controller.status, AuthGateStatus.unprovisioned);
    });

    test('no verdict (null): loading -> error (fail closed)', () async {
      final loader = _FakeLoader((_) async => null);
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();

      expect(controller.status, AuthGateStatus.error);
    });

    test('loader throws: loading -> error (fail closed)', () async {
      final loader = _FakeLoader((_) async => throw Exception('boom'));
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();

      expect(controller.status, AuthGateStatus.error);
    });
  });

  group('retry', () {
    test('unprovisioned -> trusted with forceClaimRefresh true', () async {
      var owner = false;
      final loader = _FakeLoader(
        (_) async => owner ? {'owner': true} : <String, dynamic>{},
      );
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();
      expect(controller.status, AuthGateStatus.unprovisioned);

      owner = true;
      await controller.retry();

      expect(controller.status, AuthGateStatus.trusted);
      expect(loader.calls, hasLength(2));
      expect(loader.calls.first.forceClaimRefresh, isFalse);
      expect(loader.calls.last.forceClaimRefresh, isTrue);
    });

    test('still missing claim: unprovisioned', () async {
      final loader = _FakeLoader((_) async => <String, dynamic>{});
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();
      await controller.retry();

      expect(controller.status, AuthGateStatus.unprovisioned);
    });

    test('network failure during retry: error', () async {
      var fail = false;
      final loader = _FakeLoader(
        (_) async => fail ? null : <String, dynamic>{},
      );
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();
      expect(controller.status, AuthGateStatus.unprovisioned);

      fail = true;
      await controller.retry();
      expect(controller.status, AuthGateStatus.error);
    });
  });

  group('revalidate', () {
    test('trusted + transient failure stays trusted', () async {
      var fail = false;
      final loader = _FakeLoader((_) async => fail ? null : {'owner': true});
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();
      expect(controller.status, AuthGateStatus.trusted);

      fail = true;
      await controller.revalidate();

      expect(controller.status, AuthGateStatus.trusted);
    });

    test('trusted -> unprovisioned when owner claim revoked', () async {
      var owner = true;
      final loader = _FakeLoader(
        (_) async => owner ? {'owner': true} : <String, dynamic>{},
      );
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();
      expect(controller.status, AuthGateStatus.trusted);

      owner = false;
      await controller.revalidate();

      expect(controller.status, AuthGateStatus.unprovisioned);
    });

    test('unprovisioned -> trusted when owner claim added', () async {
      var owner = false;
      final loader = _FakeLoader(
        (_) async => owner ? {'owner': true} : <String, dynamic>{},
      );
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();
      expect(controller.status, AuthGateStatus.unprovisioned);

      owner = true;
      await controller.revalidate();

      expect(controller.status, AuthGateStatus.trusted);
    });

    test('unprovisioned + transient failure stays unprovisioned', () async {
      var fail = false;
      final loader = _FakeLoader(
        (_) async => fail ? null : <String, dynamic>{},
      );
      final controller = AuthGateController(loadClaims: loader.call);

      await controller.bootstrap();
      expect(controller.status, AuthGateStatus.unprovisioned);

      fail = true;
      await controller.revalidate();

      expect(controller.status, AuthGateStatus.unprovisioned);
    });

    test('no-op while a bootstrap/retry is in flight', () async {
      var started = false;
      var done = Completer<void>();
      final loader = _FakeLoader((_) async {
        if (!started) {
          started = true;
          await done.future;
        }
        return {'owner': true};
      });
      final controller = AuthGateController(loadClaims: loader.call);

      final boot = controller.bootstrap();
      await controller.revalidate();
      done.complete();
      await boot;

      expect(loader.calls, hasLength(1));
      expect(controller.status, AuthGateStatus.trusted);
    });
  });

  group('malformed claims never grant trust', () {
    test('non-boolean owner is not trusted', () async {
      for (final value in ['yes', 1, 'true', null, '1']) {
        final loader = _FakeLoader((_) async => {'owner': value});
        final controller = AuthGateController(loadClaims: loader.call);

        await controller.bootstrap();

        expect(controller.status, AuthGateStatus.unprovisioned);
      }
    });
  });

  group('uid resolution', () {
    test('unprovisioned exposes the uid provider result', () async {
      final loader = _FakeLoader((_) async => <String, dynamic>{});
      final controller = AuthGateController(
        loadClaims: loader.call,
        loadUid: () async => 'test-uid',
      );

      await controller.bootstrap();

      expect(controller.status, AuthGateStatus.unprovisioned);
      expect(controller.uid, 'test-uid');
    });
  });
}
