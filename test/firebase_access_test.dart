import 'package:esh/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trusted-device access requires owner or controller claim', () {
    expect(hasTrustedDeviceClaim(null), isFalse);
    expect(hasTrustedDeviceClaim(const {}), isFalse);
    expect(hasTrustedDeviceClaim(const {'owner': false}), isFalse);
    expect(hasTrustedDeviceClaim(const {'owner': true}), isTrue);
    expect(hasTrustedDeviceClaim(const {'controller': true}), isTrue);
  });
}
