import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/auth/account_identity.dart';

void main() {
  group('isValidUsername', () {
    test('accepts 3-30 ASCII letters, digits, underscores, and hyphens', () {
      expect(isValidUsername('abc'), isTrue);
      expect(isValidUsername('a' * 30), isTrue);
      expect(isValidUsername('A_user-1'), isTrue);
    });

    test('rejects invalid lengths and unsupported characters', () {
      expect(isValidUsername('ab'), isFalse);
      expect(isValidUsername('a' * 31), isFalse);
      expect(isValidUsername('user.name'), isFalse);
      expect(isValidUsername('ผู้ใช้'), isFalse);
    });
  });
}
