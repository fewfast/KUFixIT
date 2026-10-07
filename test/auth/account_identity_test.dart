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

  group('isStrongPassword', () {
    test('requires length and all four character classes', () {
      expect(isStrongPassword('Abcde1!x'), isTrue);
      expect(isStrongPassword('Abcd1!x'), isFalse);
      expect(isStrongPassword('StrongPass1!'), isTrue);
      expect(isStrongPassword('Short1!'), isFalse);
      expect(isStrongPassword('lowercaseonly1!'), isFalse);
      expect(isStrongPassword('Uppercaseonly1!'), isTrue);
      expect(isStrongPassword('NoNumberPass!!'), isFalse);
      expect(isStrongPassword('NoSymbolPass12'), isFalse);
      expect(isStrongPassword('${'a' * 126}A1!'), isFalse);
    });

    test('reports each missing password requirement', () {
      expect(passwordRequirementStatus('abc'), {
        'อักขระอย่างน้อย 8 ตัว': false,
        'ตัวอักษรพิมพ์เล็กอย่างน้อย 1 ตัวอักษร': true,
        'ตัวอักษรพิมพ์ใหญ่อย่างน้อย 1 ตัวอักษร': false,
        'ตัวเลขอย่างน้อย 1 ตัวเลข': false,
        'ตัวอักษรพิเศษอย่างน้อย 1 ตัวอักษร': false,
      });
    });
  });
}
