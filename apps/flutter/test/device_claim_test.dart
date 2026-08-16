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

  group('hasOwnerClaim', () {
    test('accepts owner true', () {
      expect(hasOwnerClaim(const {'owner': true}), isTrue);
    });

    test('accepts owner true even when controller is also true', () {
      expect(hasOwnerClaim(const {'owner': true, 'controller': true}), isTrue);
    });

    test('rejects controller true without owner (Flutter gate)', () {
      expect(hasOwnerClaim(const {'controller': true}), isFalse);
    });

    test('rejects owner false with controller true (Flutter gate)', () {
      expect(
        hasOwnerClaim(const {'owner': false, 'controller': true}),
        isFalse,
      );
    });

    test('rejects null and empty claims', () {
      expect(hasOwnerClaim(null), isFalse);
      expect(hasOwnerClaim(const <String, dynamic>{}), isFalse);
    });

    test('fails closed on malformed or unexpected claim values', () {
      expect(hasOwnerClaim(const {'owner': 'yes'}), isFalse);
      expect(hasOwnerClaim(const {'owner': 1}), isFalse);
      expect(hasOwnerClaim(const {'owner': 'true'}), isFalse);
      expect(hasOwnerClaim(const {'owner': null}), isFalse);
      expect(hasOwnerClaim(const {'owner': '1'}), isFalse);
    });
  });

  group('owner vs controller (Issue #18)', () {
    test('controller true alone never unlocks the Flutter application', () {
      expect(hasOwnerClaim(const {'controller': true}), isFalse);
      expect(
        hasOwnerClaim(const {'owner': false, 'controller': true}),
        isFalse,
      );
    });

    test('owner true unlocks the Flutter application', () {
      expect(hasOwnerClaim(const {'owner': true}), isTrue);
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
