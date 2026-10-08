import 'package:supabase_flutter/supabase_flutter.dart';

String functionErrorMessage(Object error, String fallback) {
  final errorText = error.toString();
  final normalizedError = errorText.toLowerCase();
  if (normalizedError.contains('unsupported provider') &&
      normalizedError.contains('provider is not enabled')) {
    return 'ยังไม่ได้เปิดใช้ Google ใน Supabase: ไปที่ Authentication > Sign In / Providers > Google แล้วเปิดใช้งานพร้อมตั้งค่า Client ID และ Client Secret';
  }
  if (error is! FunctionsHttpException) return '$fallback: $errorText';

  final details = error.details;
  if (details is Map && details['error'] is String) {
    return details['error'] as String;
  }

  return switch (error.status) {
    401 => 'บัญชี Google ไม่ถูกต้อง กรุณาลองเข้าสู่ระบบอีกครั้ง',
    409 => 'บัญชี Google นี้อาจมีบัญชี KUFixIT แล้ว หรือ Username ถูกใช้แล้ว',
    429 => 'ทำรายการบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่',
    _ => '$fallback (HTTP ${error.status})',
  };
}
