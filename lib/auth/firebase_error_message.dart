import 'package:firebase_auth/firebase_auth.dart';

import 'account_session.dart';

String firebaseErrorMessage(Object error, String fallback) {
  if (error is UsernameUnavailableException) {
    return 'ชื่อบัญชีนี้ถูกใช้แล้ว';
  }
  if (error is ProfileSavedPasswordUpdateException) {
    return 'บันทึกข้อมูลโปรไฟล์แล้ว แต่เปลี่ยนรหัสผ่านไม่สำเร็จ '
        '(กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง): '
        '${error.cause.message ?? error.cause.code}';
  }
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'operation-not-allowed' || 'admin-restricted-operation' =>
        'Firebase ยังไม่เปิดวิธีเข้าสู่ระบบ Email/Password '
            'ให้ไปที่ Firebase Console → Authentication → Sign-in method '
            'แล้วเปิด Email/Password',
      'email-already-in-use' => 'ชื่อบัญชีนี้ถูกใช้แล้ว',
      'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
      'invalid-credential' ||
      'user-not-found' ||
      'wrong-password' => 'Username หรือรหัสผ่านไม่ถูกต้อง',
      'weak-password' => 'รหัสผ่านไม่ปลอดภัยเพียงพอ',
      'too-many-requests' => 'ทำรายการบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่',
      'requires-recent-login' =>
        'กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ก่อนเปลี่ยนรหัสผ่าน',
      'network-request-failed' =>
        'เชื่อมต่ออินเทอร์เน็ตไม่ได้ กรุณาลองอีกครั้ง',
      _ => '$fallback: ${error.message ?? error.code}',
    };
  }
  if (error is FirebaseException) {
    return '$fallback: ${error.message ?? error.code}';
  }
  if (error is StateError) return error.message.toString();
  return '$fallback: $error';
}
