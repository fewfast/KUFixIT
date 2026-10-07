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
      'firstname': 'Test',
      'lastname': 'User',
      'role': 'Admin',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });

    expect(session.account?.id, '12');
    expect(session.account?.displayName, 'Test User');
    expect(session.account?.role, 'Admin');
    expect(session.account?.accessToken, 'signed-token');
  });

  test('updates the current account profile without replacing its session', () {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    session.setFromResponse({
      'id': 12,
      'username': 'test_user',
      'firstname': 'Test',
      'lastname': 'User',
      'role': 'User',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });

    session.updateProfile(
      firstName: 'New',
      lastName: 'Name',
      username: 'new_user',
    );

    expect(session.account?.displayName, 'New Name');
    expect(session.account?.username, 'new_user');
    expect(session.account?.accessToken, 'signed-token');
    expect(session.account?.id, '12');
  });

  test('rejects expired or incomplete temporary sessions', () {
    expect(
      () => session.setFromResponse({
        'id': 12,
        'username': 'test_user',
        'firstname': 'Test',
        'lastname': 'User',
        'role': 'User',
        'accessToken': 'signed-token',
        'expiresAt': 1,
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
