import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobileproject/gui/ticket_load_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('formatTicketLoadError', () {
    test('handles FunctionsFetchException with Connection reset by peer as network error', () {
      const error = FunctionsFetchException(
        details:
            'ClientException: Connection reset by peer, uri=https://vmgzyenvqsfhcuropzjd.supabase.co/functions/v1/list-public-tickets',
      );
      final info = formatTicketLoadError(error);

      expect(info.title, 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้');
      expect(
        info.message,
        'สัญญาณอินเทอร์เน็ตอาจขัดข้องหรือหลุดระหว่างดาวน์โหลดข้อมูล กรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่อีกครั้ง',
      );
      expect(info.isNetworkError, isTrue);
      expect(info.rawDetails, contains('Connection reset by peer'));
    });

    test('handles SocketException as network error', () {
      final error = SocketException('OS Error: Network is unreachable, errno = 101');
      final info = formatTicketLoadError(error);

      expect(info.title, 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้');
      expect(info.isNetworkError, isTrue);
      expect(info.rawDetails, contains('Network is unreachable'));
    });

    test('handles http.ClientException as network error', () {
      final error = http.ClientException('Connection reset by peer');
      final info = formatTicketLoadError(error);

      expect(info.title, 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้');
      expect(info.isNetworkError, isTrue);
      expect(info.rawDetails, contains('Connection reset by peer'));
    });

    test('handles FunctionsHttpException 500 as server error', () {
      const error = FunctionsHttpException(
        status: 500,
        details: '{"error":"Internal Database Error"}',
      );
      final info = formatTicketLoadError(error);

      expect(info.title, 'ระบบเซิร์ฟเวอร์ขัดข้องชั่วคราว');
      expect(
        info.message,
        'ระบบเซิร์ฟเวอร์ไม่สามารถตอบสนองได้ชั่วคราว กรุณาลองใหม่อีกครั้งภายหลัง',
      );
      expect(info.isNetworkError, isFalse);
      expect(info.rawDetails, contains('Internal Database Error'));
    });

    test('handles FunctionsRelayException as server error', () {
      const error = FunctionsRelayException(
        status: 502,
        details: 'Bad gateway',
      );
      final info = formatTicketLoadError(error);

      expect(info.title, 'ระบบเซิร์ฟเวอร์ขัดข้องชั่วคราว');
      expect(
        info.message,
        'ระบบเซิร์ฟเวอร์ไม่สามารถตอบสนองได้ชั่วคราว กรุณาลองใหม่อีกครั้งภายหลัง',
      );
      expect(info.isNetworkError, isFalse);
    });

    test('handles FormatException or unexpected error as generic format error', () {
      const error = FormatException('รูปแบบข้อมูลรายการ Ticket ไม่ถูกต้อง');
      final info = formatTicketLoadError(error);

      expect(info.title, 'เกิดข้อผิดพลาดในการโหลดรายการ');
      expect(
        info.message,
        'เกิดข้อผิดพลาดในการโหลดรายการ กรุณาลองใหม่อีกครั้ง',
      );
      expect(info.isNetworkError, isFalse);
      expect(info.rawDetails, contains('รูปแบบข้อมูลรายการ Ticket ไม่ถูกต้อง'));
    });
  });
}
