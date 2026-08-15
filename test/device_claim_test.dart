import 'package:esh/auth/device_claim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasTrustedDeviceClaim', () {
    test('rejects null and empty claims', () {
      expect(hasTrustedDeviceClaim(null), isFalse);
      expect(hasTrustedDeviceClaim(const <String, dynamic>{}), isFalse);
    });

    test('accepts owner true', () {
      expect(hasTrustedDeviceClaim(const {'owner': true}), isTrue);
    });

    test('accepts controller true', () {
      expect(hasTrustedDeviceClaim(const {'controller': true}), isTrue);
    });

    test('accepts both claims true', () {
      expect(
        hasTrustedDeviceClaim(const {'owner': true, 'controller': true}),
        isTrue,
      );
    });

    test('rejects false owner values', () {
      expect(hasTrustedDeviceClaim(const {'owner': false}), isFalse);
      expect(
        hasTrustedDeviceClaim(const {'owner': false, 'controller': false}),
        isFalse,
      );
      expect(
        hasTrustedDeviceClaim(const {'owner': false, 'controller': true}),
        isTrue,
      );
    });

    test('rejects false controller values', () {
      expect(hasTrustedDeviceClaim(const {'controller': false}), isFalse);
      expect(
        hasTrustedDeviceClaim(const {'owner': true, 'controller': false}),
        isTrue,
      );
    });

    test('fails closed on malformed or unexpected claim values', () {
      expect(hasTrustedDeviceClaim(const {'owner': 'yes'}), isFalse);
      expect(hasTrustedDeviceClaim(const {'controller': 1}), isFalse);
      expect(hasTrustedDeviceClaim(const {'owner': 'true'}), isFalse);
      expect(hasTrustedDeviceClaim(const {'owner': null}), isFalse);
      expect(hasTrustedDeviceClaim(const {'owner': '1'}), isFalse);
    });
  });

  group('revalidateTrust', () {
    test('returns null (keep current) when claims cannot be loaded', () {
      expect(revalidateTrust(null), isNull);
    });

    test('reports untrusted for empty claims', () {
      expect(revalidateTrust(const <String, dynamic>{}), DeviceTrust.untrusted);
    });

    test('reports trusted for owner claim', () {
      expect(revalidateTrust(const {'owner': true}), DeviceTrust.trusted);
    });

    test('reports trusted for controller claim', () {
      expect(revalidateTrust(const {'controller': true}), DeviceTrust.trusted);
    });

    test('reports untrusted for false/malformed claims', () {
      expect(revalidateTrust(const {'owner': false}), DeviceTrust.untrusted);
      expect(revalidateTrust(const {'owner': 'yes'}), DeviceTrust.untrusted);
    });
  });

  group('provisioning transition', () {
    test(
      'empty token then refreshed owner token flips untrusted to trusted',
      () {
        // The client still holds the token issued before provisioning.
        expect(
          revalidateTrust(const <String, dynamic>{}),
          DeviceTrust.untrusted,
        );

        // After the administrator assigns the claim and the client refreshes,
        // the same predicate reports trusted.
        expect(revalidateTrust(const {'owner': true}), DeviceTrust.trusted);
      },
    );

    test('controller claim follows the same transition', () {
      expect(revalidateTrust(const <String, dynamic>{}), DeviceTrust.untrusted);
      expect(revalidateTrust(const {'controller': true}), DeviceTrust.trusted);
    });
  });
}
