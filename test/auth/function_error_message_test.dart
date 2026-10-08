import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/auth/function_error_message.dart';

void main() {
  test('explains when the Google provider is disabled in Supabase', () {
    final message = functionErrorMessage(
      Exception(
        '{"code":400,"error_code":"validation_failed",'
        '"msg":"Unsupported provider: provider is not enabled"}',
      ),
      'Google sign-in failed',
    );

    expect(message, contains('Authentication > Sign In / Providers > Google'));
    expect(message, contains('Client ID'));
    expect(message, isNot(contains('validation_failed')));
  });
}
