import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/ticket_update_error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('shows actionable server validation text', () {
    const message = 'กรุณากำหนดช่วงเวลาเริ่มและสิ้นสุดการซ่อมให้ถูกต้อง';
    expect(
      ticketUpdateErrorMessage(
        const FunctionsHttpException(
          status: 400,
          details:
              '{"error":"กรุณากำหนดช่วงเวลาเริ่มและสิ้นสุดการซ่อมให้ถูกต้อง"}',
        ),
      ),
      message,
    );
  });

  test('shows a safe connection message for fetch timeout/failure', () {
    final message = ticketUpdateErrorMessage(
      const FunctionsFetchException(
        details: 'TimeoutException with private detail',
      ),
    );
    expect(message, contains('ตรวจสอบเครือข่าย'));
    expect(message, isNot(contains('private detail')));
  });

  test('shows a safe message for relay failures', () {
    final message = ticketUpdateErrorMessage(
      const FunctionsRelayException(
        status: 502,
        details: 'internal relay data',
      ),
    );
    expect(message, contains('ยังไม่พร้อม'));
    expect(message, isNot(contains('internal relay data')));
  });

  test('does not expose server details for an unknown 500', () {
    final message = ticketUpdateErrorMessage(
      const FunctionsHttpException(status: 500, details: 'private SQL stack'),
    );
    expect(message, 'ระบบบันทึกคำร้องไม่สำเร็จ กรุณาลองใหม่ภายหลัง');
    expect(message, isNot(contains('private SQL stack')));
  });

  test('shows a safe correlation ID for internal server errors', () {
    const id = '1f5d3a20-0674-4d6a-9a4d-7eae47ba09de';
    final message = ticketUpdateErrorMessage(
      FunctionsHttpException(
        status: 500,
        details:
            '{"error":"private detail","correlationId":"1f5d3a20-0674-4d6a-9a4d-7eae47ba09de"}',
      ),
    );
    expect(message, contains(id));
    expect(message, isNot(contains('private detail')));
  });

  test('does not show malformed correlation IDs', () {
    final message = ticketUpdateErrorMessage(
      const FunctionsHttpException(
        status: 500,
        details: '{"correlationId":"ticket-123"}',
      ),
    );
    expect(message, isNot(contains('ticket-123')));
  });
}
