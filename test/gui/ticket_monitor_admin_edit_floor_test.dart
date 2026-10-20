import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/ticketMonitor.dart';

void main() {
  final sampleAdminTicket = {
    'TicketId': '1234567890',
    'request_date': '2026-10-20T10:00:00+07:00',
    'building': '1',
    'area': null,
    'floor': '2',
    'room': '201',
    'status': 'finish',
    'technician_team': 'ทีมช่างไฟฟ้า',
    'requester_uid': '1020304050',
    'requester_display_name': 'สมชาย ใจดี',
  };

  testWidgets('admin edit ticket dialog enforces floor limits (1-50, digits only)', (
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

    Future<Map<String, dynamic>> mockFetchDevices(String ticketId) async {
      return {
        'devices': [
          {
            'deviceid': 1,
            'device': 'แอร์',
            'status': 'finish',
            'discription': null,
            'next_fix_date': null,
            'technician_comment': [],
          }
        ],
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketMonitor(
            adminMode: true,
            fetchTickets: mockFetch,
            fetchDevices: mockFetchDevices,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Expand ticket row
    await tester.tap(find.text('1234567890'));
    await tester.pumpAndSettle();

    // Tap edit button
    final editButton = find.byTooltip('แก้ไขข้อมูลคำร้อง');
    expect(editButton, findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    // Verify dialog opened
    expect(find.text('แก้ไขคำร้อง 1234567890'), findsOneWidget);

    // Find floor field
    final floorFieldFinder = find.widgetWithText(TextFormField, 'ชั้น *');
    expect(floorFieldFinder, findsOneWidget);

    final textField = tester.widget<TextField>(
      find.descendant(of: floorFieldFinder, matching: find.byType(TextField)),
    );
    expect(textField.keyboardType, TextInputType.number);

    // Initial floor value is '2'
    expect(find.text('2'), findsWidgets);

    // Try typing non-digits: should not accept letters
    await tester.enterText(floorFieldFinder, 'abc');
    await tester.pumpAndSettle();
    expect(find.text('abc'), findsNothing);

    // Enter valid floor 50
    await tester.enterText(floorFieldFinder, '50');
    await tester.pumpAndSettle();
    expect(find.text('50'), findsOneWidget);

    // Try typing 51 or 100: formatter rejects > 50
    await tester.enterText(floorFieldFinder, '51');
    await tester.pumpAndSettle();
    expect(find.text('51'), findsNothing);

    await tester.enterText(floorFieldFinder, '100');
    await tester.pumpAndSettle();
    expect(find.text('100'), findsNothing);

    // Test validator: empty floor for non-other building
    await tester.enterText(floorFieldFinder, '');
    await tester.pumpAndSettle();

    final saveButton = find.text('บันทึก');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('กรุณาระบุชั้น'), findsOneWidget);

    // Test validator for invalid values like 0 (if entered)
    textField.controller?.text = '0';
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('กรุณาระบุชั้นเป็นตัวเลขระหว่าง 1 ถึง 50'), findsOneWidget);
  });
}
