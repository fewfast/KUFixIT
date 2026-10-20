import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/ticketMonitor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('displays network error card and retries successfully upon tapping button', (
    tester,
  ) async {
    var callCount = 0;

    Future<Map<String, dynamic>> mockFetch({
      required bool myRequests,
      required bool adminMode,
      required String ticketId,
      required int page,
      required int pageSize,
      required String sortBy,
      required bool sortAscending,
    }) async {
      callCount++;
      if (callCount == 1) {
        throw const FunctionsFetchException(
          details:
              'ClientException: Connection reset by peer, uri=https://vmgzyenvqsfhcuropzjd.supabase.co/functions/v1/list-public-tickets',
        );
      }
      return {
        'tickets': [
          {
            'TicketId': 'T1001',
            'request_date': '2026-10-20T10:00:00Z',
            'building': 'อาคาร 1',
            'area': 'ทั่วไป',
            'floor': '1',
            'room': '101',
            'status': 'validating',
            'latest_edited': '2026-10-20T10:00:00Z',
          }
        ],
        'total': 1,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketMonitor(
            adminMode: false,
            fetchTickets: mockFetch,
          ),
        ),
      ),
    );

    // Initial load fails with network error
    await tester.pumpAndSettle();

    // Verify error UI
    expect(find.text('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้'), findsOneWidget);
    expect(
      find.textContaining('สัญญาณอินเทอร์เน็ตอาจขัดข้องหรือหลุด'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.text('ลองใหม่อีกครั้ง'), findsOneWidget);
    expect(find.text('ดูรายละเอียดข้อผิดพลาด'), findsOneWidget);

    // Raw technical details should not be visible initially
    expect(find.textContaining('Connection reset by peer'), findsNothing);

    // Tap to expand technical details
    final detailsButton = find.text('ดูรายละเอียดข้อผิดพลาด');
    await tester.ensureVisible(detailsButton);
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    expect(find.text('ซ่อนรายละเอียดทางเทคนิค'), findsOneWidget);
    expect(find.textContaining('Connection reset by peer'), findsOneWidget);

    // Tap "ลองใหม่อีกครั้ง"
    final retryButton = find.text('ลองใหม่อีกครั้ง');
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);
    await tester.pump(); // Start loading
    await tester.pumpAndSettle(); // Settle with loaded tickets

    expect(callCount, 2);
    expect(find.text('T1001'), findsOneWidget);
    expect(find.text('อาคาร 1'), findsOneWidget);
    expect(find.text('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้'), findsNothing);
  });

  testWidgets('displays server error card with cloud icon on 500 status', (
    tester,
  ) async {
    Future<Map<String, dynamic>> mockFetch500({
      required bool myRequests,
      required bool adminMode,
      required String ticketId,
      required int page,
      required int pageSize,
      required String sortBy,
      required bool sortAscending,
    }) async {
      throw const FunctionsHttpException(
        status: 500,
        details: '{"error":"Internal Database Error"}',
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketMonitor(
            adminMode: false,
            fetchTickets: mockFetch500,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ระบบเซิร์ฟเวอร์ขัดข้องชั่วคราว'), findsOneWidget);
    expect(
      find.text('ระบบเซิร์ฟเวอร์ไม่สามารถตอบสนองได้ชั่วคราว กรุณาลองใหม่อีกครั้งภายหลัง'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text('ลองใหม่อีกครั้ง'), findsOneWidget);
  });
}
