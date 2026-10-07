import 'package:supabase_flutter/supabase_flutter.dart';

String functionErrorMessage(Object error, String fallback) {
  if (error is! FunctionsHttpException) return '$fallback: $error';

  final details = error.details;
  if (details is Map && details['error'] is String) {
    return details['error'] as String;
  }

  return switch (error.status) {
    401 => 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง',
    409 => 'ชื่อผู้ใช้นี้ถูกใช้แล้ว',
    429 => 'ทำรายการบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่',
    _ => '$fallback (HTTP ${error.status})',
  };
}
