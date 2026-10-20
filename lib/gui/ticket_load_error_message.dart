import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class TicketLoadErrorInfo {
  final String title;
  final String message;
  final String rawDetails;
  final bool isNetworkError;

  const TicketLoadErrorInfo({
    required this.title,
    required this.message,
    required this.rawDetails,
    this.isNetworkError = false,
  });

  @override
  String toString() => '$title: $message';
}

TicketLoadErrorInfo formatTicketLoadError(Object error) {
  final errorText = error.toString();
  final lowerText = errorText.toLowerCase();

  final isNetwork = error is FunctionsFetchException ||
      error is SocketException ||
      error is http.ClientException ||
      lowerText.contains('connection reset') ||
      lowerText.contains('network is unreachable') ||
      lowerText.contains('connection refused') ||
      lowerText.contains('connection closed') ||
      lowerText.contains('failed host lookup') ||
      lowerText.contains('clientexception') ||
      lowerText.contains('socketexception') ||
      lowerText.contains('timed out') ||
      lowerText.contains('timeout') ||
      (error is FunctionsHttpException && error.status == 0) ||
      lowerText.contains('status: 0') ||
      lowerText.contains('status 0');

  if (isNetwork) {
    return TicketLoadErrorInfo(
      title: 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้',
      message:
          'สัญญาณอินเทอร์เน็ตอาจขัดข้องหรือหลุดระหว่างดาวน์โหลดข้อมูล กรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่อีกครั้ง',
      rawDetails: errorText,
      isNetworkError: true,
    );
  }

  final isServerError =
      (error is FunctionsHttpException && error.status >= 500) ||
      error is FunctionsRelayException ||
      lowerText.contains('502 bad gateway') ||
      lowerText.contains('503 service unavailable') ||
      lowerText.contains('504 gateway timeout') ||
      lowerText.contains('internal server error');

  if (isServerError) {
    return TicketLoadErrorInfo(
      title: 'ระบบเซิร์ฟเวอร์ขัดข้องชั่วคราว',
      message:
          'ระบบเซิร์ฟเวอร์ไม่สามารถตอบสนองได้ชั่วคราว กรุณาลองใหม่อีกครั้งภายหลัง',
      rawDetails: errorText,
      isNetworkError: false,
    );
  }

  return TicketLoadErrorInfo(
    title: 'เกิดข้อผิดพลาดในการโหลดรายการ',
    message: 'เกิดข้อผิดพลาดในการโหลดรายการ กรุณาลองใหม่อีกครั้ง',
    rawDetails: errorText,
    isNetworkError: false,
  );
}

