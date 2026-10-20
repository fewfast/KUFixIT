import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/ticketMonitor.dart';

void main() {
  final sampleAdminTicket = {
    'TicketId': '1234567890',
    'request_date': '2026-10-20T10:00:00+07:00',
    'building': 'อาคาร 1',
    'area': null,
    'floor': '2',
    'room': '201',
    'status': 'pending',
    'technician_team': 'ทีมช่างไฟฟ้า',
    'requester_uid': '1020304050',
    'requester_display_name': 'สมชาย ใจดี',
  };

  testWidgets('adminMode shows requester info and admin search placeholder', (
    tester,
  ) async {
    Future<Map<String, dynamic>> mockFetch({
      required bool myRequests,
      required bool adminMode,
      required String ticketId,
      required int page,
      required int pageSize,
      required String sortBy,
      required bool sortAscending,
    }) async {
      return {
        'tickets': [sampleAdminTicket],
        'total': 1,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketMonitor(adminMode: true, fetchTickets: mockFetch),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify search field label and hint for adminMode
    expect(
      find.text('ค้นหา TicketId, UID หรือชื่อผู้ส่งคำร้อง'),
      findsOneWidget,
    );
    expect(
      find.text('กรอก TicketId, UID หรือชื่อผู้ส่งคำร้อง'),
      findsOneWidget,
    );

    // Verify keyboardType is text
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.keyboardType, TextInputType.text);

    // Verify ticket row rendered
    expect(find.text('1234567890'), findsOneWidget);

    // Tap on row to expand details
    await tester.tap(find.text('1234567890'));
    await tester.pumpAndSettle();

    // Verify requester info is displayed beside sub-devices header
    expect(find.text('ผู้ส่งคำร้อง สมชาย ใจดี(1020304050)'), findsOneWidget);

    // Verify edit button and repair history button are positioned on the right
    final editButtonPos = tester.getTopLeft(find.byTooltip('แก้ไขข้อมูลคำร้อง'));
    final historyButtonPos = tester.getTopLeft(find.text('ประวัติการซ่อม'));
    final requesterTextPos = tester.getTopLeft(
      find.text('ผู้ส่งคำร้อง สมชาย ใจดี(1020304050)'),
    );

    expect(editButtonPos.dx, greaterThan(requesterTextPos.dx));
    expect(historyButtonPos.dx, greaterThan(editButtonPos.dx));
  });

  testWidgets(
    'non-admin mode hides requester info and uses numeric search field',
    (tester) async {
      Future<Map<String, dynamic>> mockFetch({
        required bool myRequests,
        required bool adminMode,
        required String ticketId,
        required int page,
        required int pageSize,
        required String sortBy,
        required bool sortAscending,
      }) async {
        return {
          'tickets': [sampleAdminTicket],
          'total': 1,
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketMonitor(adminMode: false, fetchTickets: mockFetch),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify search field label and hint for non-admin mode
      expect(find.text('ค้นหา TicketId'), findsOneWidget);
      expect(find.text('กรอก TicketId'), findsOneWidget);

      // Verify keyboardType is number
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.keyboardType, TextInputType.number);

      // Tap on row to expand details
      await tester.tap(find.text('1234567890'));
      await tester.pumpAndSettle();

      // Requester info must NOT be displayed in non-admin mode
      expect(find.textContaining('ผู้ส่งคำร้อง'), findsNothing);
    },
  );
}
