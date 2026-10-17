import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/auth/temporary_account_session.dart';

void main() {
  final session = TemporaryAccountSession.instance;

  tearDown(session.clear);

  test('parses a temporary session from an Edge Function response', () {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;

    session.setFromResponse({
      'id': 12,
      'username': 'test_user',
      'uid': 'u_1234567890',
      'firstname': 'Test',
      'lastname': 'User',
      'displayname': 'Google Display Name',
      'hasNationalId': false,
      'role': 'Admin',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });

    expect(session.account?.id, '12');
    expect(session.account?.uid, 'u_1234567890');
    expect(session.account?.displayName, 'Google Display Name');
    expect(session.account?.hasNationalId, isFalse);
    expect(session.account?.role, 'Admin');
    expect(session.account?.accessToken, 'signed-token');
  });

  test('marks staff sessions as system accounts', () {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    session.setFromResponse({
      'id': 'technician1',
      'username': 'technician1',
      'firstname': 'technician1',
      'lastname': '',
      'hasNationalId': false,
      'isSystemAccount': true,
      'role': 'Technician',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });

    expect(session.account?.isSystemAccount, isTrue);
    expect(session.account?.id, 'technician1');
    expect(session.account?.role, 'Technician');
  });

  test('accepts prefixed technician UIDs and legacy numeric UIDs', () {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;

    session.setFromResponse({
      'id': 'technician1',
      'username': 'technician1',
      'uid': 't_1234567890',
      'firstname': 'technician1',
      'lastname': '',
      'isSystemAccount': true,
      'role': 'Technician',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });
    expect(session.account?.uid, 't_1234567890');

    session.setFromResponse({
      'id': 'legacy-user',
      'username': 'legacy-user',
      'uid': 1234567890,
      'firstname': 'Legacy',
      'lastname': 'User',
      'role': 'User',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });
    expect(session.account?.uid, '1234567890');
  });

  test('accepts UUID-format prefixed UIDs during backend migration', () {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;

    session.setFromResponse({
      'id': 12,
      'username': 'test_user',
      'uid': 'u_79f01ec0123443219321123456789abc',
      'firstname': 'Test',
      'lastname': 'User',
      'role': 'User',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });
    expect(session.account?.uid, 'u_79f01ec0123443219321123456789abc');

    session.setFromResponse({
      'id': 'technician1',
      'username': 'technician1',
      'uid': 't_79f01ec0123443219321123456789abc',
      'firstname': 'Technician',
      'lastname': '',
      'isSystemAccount': true,
      'role': 'Technician',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });
    expect(session.account?.uid, 't_79f01ec0123443219321123456789abc');
  });

  test('rejects prefixed UIDs without exactly 10 digits', () {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;

    expect(
      () => session.setFromResponse({
        'id': 12,
        'username': 'test_user',
        'uid': 'u_79f01ec0123443219321123456789abc12345',
        'firstname': 'Test',
        'lastname': 'User',
        'role': 'User',
        'accessToken': 'signed-token',
        'expiresAt': expiresAt,
      }),
      throwsFormatException,
    );
  });

  test('updates the current account profile without replacing its session', () {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    session.setFromResponse({
      'id': 12,
      'username': 'test_user',
      'uid': 'u_1234567890',
      'firstname': 'Test',
      'lastname': 'User',
      'role': 'User',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });

    session.updateProfile(displayName: 'New Display Name');

    expect(session.account?.displayName, 'New Display Name');
    expect(session.account?.username, 'test_user');
    expect(session.account?.uid, 'u_1234567890');
    expect(session.account?.accessToken, 'signed-token');
    expect(session.account?.id, '12');
  });

  test('rejects expired or incomplete temporary sessions', () {
    expect(
      () => session.setFromResponse({
        'id': 12,
        'username': 'test_user',
        'uid': 'u_1234567890',
        'firstname': 'Test',
        'lastname': 'User',
        'role': 'User',
        'accessToken': 'signed-token',
        'expiresAt': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => session.setFromResponse({
        'id': 'google-auth-id',
        'username': 'test_user',
        'firstname': 'Test',
        'lastname': 'User',
        'role': 'User',
        'accessToken': 'signed-token',
        'expiresAt':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }),
      throwsFormatException,
    );
    expect(
      () => session.setFromResponse({'username': 'test_user'}),
      throwsFormatException,
    );
    expect(session.account, isNull);
  });
}
