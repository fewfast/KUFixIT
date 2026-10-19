import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/function_error_message.dart';
import 'dart:convert';

String ticketUpdateErrorMessage(Object error) {
  if (error is FunctionsHttpException) {
    final details = error.details;
    dynamic decoded = details;
    if (details is String) {
      try {
        decoded = jsonDecode(details);
      } on FormatException {
        decoded = null;
      }
    }
    final correlationId = decoded is Map ? decoded['correlationId'] : null;
    final serverMessage = decoded is Map ? decoded['error'] : null;
    final safeServerMessages = <String>{
      'ระบบยังโหลดข้อกำหนดการบันทึกไม่ครบ กรุณาลองอีกครั้งภายหลัง',
      'ระบบพบข้อกำหนด RPC ซ้ำ กรุณาแจ้งผู้ดูแลระบบพร้อมรหัสตรวจสอบ',
      'ระบบไม่พบ RPC สำหรับบันทึก กรุณาแจ้งผู้ดูแลระบบพร้อมรหัสตรวจสอบ',
      'บันทึกคำร้องและการมอบหมายทีมไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    };
    final message = error.status >= 500
        ? serverMessage is String && safeServerMessages.contains(serverMessage)
              ? serverMessage
              : 'ระบบบันทึกคำร้องไม่สำเร็จ กรุณาลองใหม่ภายหลัง'
        : functionErrorMessage(error, 'บันทึกข้อมูลคำร้องไม่สำเร็จ');
    if (error.status >= 500 &&
        correlationId is String &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(correlationId)) {
      return '$message (รหัสตรวจสอบ: $correlationId)';
    }
    return message;
  }
  if (error is FunctionsFetchException) {
    return 'ติดต่อบริการบันทึกคำร้องไม่ได้ กรุณาตรวจสอบเครือข่ายก่อนลองอีกครั้ง';
  }
  if (error is FunctionsRelayException) {
    return 'บริการบันทึกคำร้องยังไม่พร้อม กรุณาลองอีกครั้งภายหลัง';
  }
  return 'บันทึกข้อมูลคำร้องไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
}
