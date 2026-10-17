import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/auth/function_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  test('returns the server message from an HTTP function response body', () {
    const serverMessage = 'ชื่อช่างนี้มีในระบบแล้ว กรุณาใช้ชื่ออื่น';
    final error = FunctionsHttpException(
      status: 409,
      details: '{"error":"$serverMessage"}',
    );

    expect(
      functionErrorMessage(error, 'เรียกบริการจัดการช่างไม่สำเร็จ'),
      serverMessage,
    );
  });
}
