import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/activity_log_page.dart';

void main() {
  testWidgets('ActivityLogPage displays logs, role badge, target chip, and details dialog', (
    tester,
  ) async {
    final sampleLogs = [
      {
        'id': 1,
        'actor_username': 'admin01',
        'actor_role': 'Admin',
        'actor_display_name': 'สมชาย แอดมิน',
        'action_type': 'REPORT_APPROVE',
        'action_title': 'อนุมัติงานช่าง',
        'description': 'อนุมัติรายงานงานซ่อม #105 อุปกรณ์ ปริ้นเตอร์',
        'target_id': '105',
        'metadata': {'uid': 'u_admin01'},
        'created_at': '2026-10-20T02:00:00+07:00',
      },
      {
        'id': 2,
        'actor_username': 'superadmin',
        'actor_role': 'SuperAdmin',
        'actor_display_name': 'Super Administrator',
        'action_type': 'ROLE_CHANGE',
        'action_title': 'เปลี่ยนบทบาทผู้ใช้',
        'description': 'เปลี่ยนบทบาทผู้ใช้ u_123 เป็น Admin',
        'target_id': 'u_123',
        'metadata': {},
        'created_at': '2026-10-20T01:30:00+07:00',
      },
      {
        'id': 3,
        'actor_username': 'tech01',
        'actor_role': 'Technician',
        'actor_display_name': 'ช่างสมชาย',
        'action_type': 'TECH_SUBMIT',
        'action_title': 'ส่งงานช่าง',
        'description': 'ส่งงานซ่อม Ticket #105',
        'target_id': '105',
        'metadata': {'team': 'techteam', 'uid': 'u_tech01'},
        'created_at': '2026-10-20T01:00:00+07:00',
      },
      {
        'id': 4,
        'actor_username': 'superadmin2',
        'actor_role': 'SuperAdmin',
        'actor_display_name': 'SuperAdmin2',
        'action_type': 'ROLE_CHANGE_REJECT',
        'action_title': 'ปฏิเสธการแก้ไขผู้ใช้',
        'description': 'ปฏิเสธคำขอ',
        'metadata': {},
        'created_at': '2026-10-20T00:30:00+07:00',
      },
      {
        'id': 5,
        'actor_username': 'u_1020304050',
        'actor_role': 'User',
        'actor_display_name': 'ผู้ใช้ทดสอบ',
        'action_type': 'CHANGE_DISPLAY_NAME',
        'action_title': 'เปลี่ยนชื่อที่แสดง',
        'description': 'ผู้ใช้งานเปลี่ยนชื่อที่แสดงเป็น ผู้ใช้ทดสอบ',
        'target_id': 'u_1020304050',
        'metadata': {'uid': 'u_1020304050', 'old_name': 'ชื่อเดิม', 'new_name': 'ผู้ใช้ทดสอบ'},
        'created_at': '2026-10-20T00:15:00+07:00',
      },
    ];

    Future<Map<String, dynamic>> mockFetchLogs({
      required int page,
      required int pageSize,
      String? search,
      String? actionType,
      String? actorRole,
      String? startDate,
      String? endDate,
    }) async {
      return {
        'logs': sampleLogs,
        'totalCount': 5,
        'page': 1,
        'pageSize': 5,
        'totalPages': 1,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ActivityLogPage(fetchLogs: mockFetchLogs),
      ),
    );

    // Pump and settle to complete loading
    await tester.pumpAndSettle();

    // Verify header
    expect(find.text('ประวัติการกระทำทั้งหมด (Activity Logs)'), findsOneWidget);

    // Verify formatted actor headers
    expect(find.text('สมชาย แอดมิน (u_admin01)'), findsOneWidget);
    expect(find.text('SuperAdmin1'), findsOneWidget);
    expect(find.text('ทีมช่าง techteam (u_tech01)'), findsOneWidget);
    expect(find.text('SuperAdmin2'), findsOneWidget);
    expect(find.text('ผู้ใช้ทดสอบ (u_1020304050)'), findsOneWidget);

    // Verify logs rendered
    expect(find.text('อนุมัติงานช่าง'), findsOneWidget);
    expect(find.text('เปลี่ยนบทบาทผู้ใช้'), findsOneWidget);
    expect(find.text('ส่งงานช่าง'), findsOneWidget);
    expect(find.text('ปฏิเสธการแก้ไขผู้ใช้'), findsOneWidget);
    expect(find.text('เปลี่ยนชื่อที่แสดง'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('SuperAdmin'), findsNWidgets(2));
    expect(find.text('Technician'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('#105'), findsNWidgets(2));
    expect(find.text('#u_123'), findsOneWidget);
    expect(find.text('#u_1020304050'), findsOneWidget);

    // Tap on card to open metadata dialog
    await tester.tap(find.text('อนุมัติงานช่าง'));
    await tester.pumpAndSettle();

    // Verify dialog opens
    expect(find.text('รายละเอียด: อนุมัติงานช่าง'), findsOneWidget);
    expect(find.text('ปิด'), findsOneWidget);

    // Close dialog
    await tester.tap(find.text('ปิด'));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียด: อนุมัติงานช่าง'), findsNothing);
  });

  testWidgets('ActivityLogPage handles search and filter submission', (
    tester,
  ) async {
    String? capturedSearch;
    String? capturedActionType;

    Future<Map<String, dynamic>> mockFetchLogs({
      required int page,
      required int pageSize,
      String? search,
      String? actionType,
      String? actorRole,
      String? startDate,
      String? endDate,
    }) async {
      capturedSearch = search;
      capturedActionType = actionType;
      return {
        'logs': [],
        'totalCount': 0,
        'page': 1,
        'pageSize': 5,
        'totalPages': 1,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ActivityLogPage(fetchLogs: mockFetchLogs),
      ),
    );
    await tester.pumpAndSettle();

    // Enter search text
    await tester.enterText(find.byType(TextField), 'Ticket 105');
    await tester.tap(find.text('ค้นหา'));
    await tester.pumpAndSettle();

    expect(capturedSearch, 'Ticket 105');
    expect(capturedActionType, 'ALL');

    // Empty state should be visible
    expect(find.text('ไม่พบประวัติการกระทำตามเงื่อนไขที่เลือก'), findsOneWidget);
  });
}
