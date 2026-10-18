// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobileproject/auth/temporary_account_session.dart';
import 'package:mobileproject/gui/database_connection_error_page.dart';
import 'package:mobileproject/gui/layout.dart';
import 'package:mobileproject/gui/personal_info_page.dart';

void main() {
  testWidgets('layout keeps the header and shows Technician navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'Technician')),
    );

    expect(find.text('KUFixIT'), findsOneWidget);
    expect(find.text('รายการงานซ่อมที่ได้รับมอบหมาย'), findsOneWidget);
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('งานที่ได้รับ'),
      ),
      findsOneWidget,
    );
    expect(find.text('หน้าหลัก'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'งานที่ได้รับ'));
    await tester.pumpAndSettle();

    expect(find.text('KUFixIT'), findsOneWidget);
    expect(find.text('รายการงานซ่อมที่ได้รับมอบหมาย'), findsOneWidget);
    expect(find.text('รายการแจ้งซ่อมของฉัน'), findsNothing);
  });

  testWidgets('Technician drawer shows username, UID, and role', (
    tester,
  ) async {
    TemporaryAccountSession.instance.setFromResponse({
      'id': 'testTicket',
      'username': 'testTicket',
      'uid': 't_1234567890',
      'accessUntil':
          DateTime.now()
              .add(const Duration(hours: 25))
              .millisecondsSinceEpoch ~/
          1000,
      'accessRangeStart': '2026-10-17',
      'accessRangeEnd': '2026-10-18',
      'firstname': 'testTicket',
      'lastname': '',
      'role': 'Technician',
      'isSystemAccount': true,
      'accessToken': 'signed-token',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
    });

    await tester.pumpWidget(const MaterialApp(home: Layout()));
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    expect(find.text('username: testTicket'), findsOneWidget);
    expect(find.text('UID: t_1234567890'), findsOneWidget);
    expect(find.text('Role: Technician'), findsOneWidget);
    expect(find.text('ช่วงเวลางาน: 17/10/2569 - 18/10/2569'), findsOneWidget);
    expect(find.text('อายุบัญชีที่เหลือ: 1 วัน 1 ชม.'), findsOneWidget);
    expect(find.text('บัญชี: testTicket'), findsNothing);

    TemporaryAccountSession.instance.clear();
  });

  testWidgets('User role gets request navigation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'User')),
    );

    expect(find.text('ค้นหา TicketId'), findsOneWidget);
    expect(find.byTooltip('รีเฟรชรายการ'), findsOneWidget);
    expect(find.text('ยังไม่ได้เชื่อมต่อ Supabase'), findsOneWidget);

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    expect(find.text('แจ้งซ่อม'), findsOneWidget);
    expect(find.text('รายการแจ้งซ่อมของฉัน'), findsOneWidget);
    expect(find.text('จัดการผู้ใช้'), findsNothing);
    final menuLabels = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(
      menuLabels.indexOf('รายการแจ้งซ่อมของฉัน'),
      lessThan(menuLabels.indexOf('แจ้งซ่อม')),
    );
  });

  testWidgets('Admin home is the repair monitor navigation item', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'Admin')),
    );

    expect(find.text('ติดตามงานซ่อม'), findsOneWidget);
    expect(find.text('ค้นหา TicketId'), findsOneWidget);
    expect(find.text('กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลระบบ'), findsOneWidget);

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    expect(
      find.descendant(of: drawer, matching: find.text('หน้าหลัก')),
      findsNothing,
    );
    expect(
      find.descendant(of: drawer, matching: find.text('คำร้องแจ้งซ่อม')),
      findsOneWidget,
    );
    final menuLabels = tester
        .widgetList<ListTile>(
          find.descendant(of: drawer, matching: find.byType(ListTile)),
        )
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(menuLabels.first, 'คำร้องแจ้งซ่อม');
    expect(menuLabels.where((label) => label == 'คำร้องแจ้งซ่อม').length, 1);
  });

  testWidgets('SuperAdmin drawer omits restricted navigation items', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'SuperAdmin')),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    final drawer = find.byType(Drawer);
    for (final label in ['หน้าหลัก', 'จัดการช่างเทคนิค', 'ตั้งค่าระบบ']) {
      expect(
        find.descendant(of: drawer, matching: find.text(label)),
        findsNothing,
      );
    }
    for (final label in [
      'คำร้องแจ้งซ่อม',
      'จัดการผู้ใช้',
      'ยืนยันการกระทำ',
      'รายงาน',
    ]) {
      expect(
        find.descendant(of: drawer, matching: find.text(label)),
        findsOneWidget,
      );
    }

    final menuLabels = tester
        .widgetList<ListTile>(
          find.descendant(of: drawer, matching: find.byType(ListTile)),
        )
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(menuLabels, [
      'คำร้องแจ้งซ่อม',
      'จัดการผู้ใช้',
      'ยืนยันการกระทำ',
      'รายงาน',
    ]);

    await tester.tap(find.text('จัดการผู้ใช้'));
    await tester.pumpAndSettle();
    expect(find.text('ค้นหา user'), findsOneWidget);
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันการกระทำ'));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันการกระทำ'), findsOneWidget);
  });

  testWidgets(
    'Admin can open technician management between users and reports',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Layout(roleOverride: 'Admin')),
      );

      await tester.tap(find.byTooltip('เปิดเมนู'));
      await tester.pumpAndSettle();

      final menuLabels = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(
        menuLabels.indexOf('จัดการช่างเทคนิค'),
        menuLabels.indexOf('จัดการผู้ใช้') + 1,
      );
      expect(
        menuLabels.indexOf('จัดการช่างเทคนิค'),
        lessThan(menuLabels.indexOf('รายงาน')),
      );

      await tester.tap(find.text('จัดการช่างเทคนิค'));
      await tester.pumpAndSettle();
      expect(find.text('จัดการบัญชีและข้อมูลช่างเทคนิค'), findsOneWidget);
    },
  );

  testWidgets('User can open their own repair request list', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'User')),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายการแจ้งซ่อมของฉัน'));
    await tester.pumpAndSettle();

    expect(find.text('รายการแจ้งซ่อมของฉัน'), findsOneWidget);
    expect(find.byTooltip('รีเฟรชรายการ'), findsOneWidget);
    expect(
      find.text('กรุณาเข้าสู่ระบบเพื่อดูรายการแจ้งซ่อมของคุณ'),
      findsOneWidget,
    );
  });

  testWidgets('User can open the repair request form', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'User')),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แจ้งซ่อม'));
    await tester.pumpAndSettle();

    expect(
      find.text('เลือกอาคารและระบุรายละเอียดอุปกรณ์ที่ต้องการแจ้งซ่อม'),
      findsOneWidget,
    );
    expect(find.text('อาคาร'), findsOneWidget);
    expect(find.text('ชั้นที่ (ถ้ามี, ไม่เกิน 50 ชั้น)'), findsOneWidget);
    expect(find.text('เลขห้อง (ถ้ามี)'), findsOneWidget);
    expect(find.text('ชื่ออุปกรณ์ที่พัง'), findsOneWidget);
    expect(find.text('เพิ่มรูปถ่าย'), findsOneWidget);
    expect(find.text('ข้อมูลเพิ่มเติม'), findsOneWidget);
  });

  testWidgets('repair form supports other locations and additional items', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'User')),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แจ้งซ่อม'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, 'อื่น');
    await tester.pumpAndSettle();
    await tester.tap(find.text('อื่นๆ').last);
    await tester.pumpAndSettle();

    expect(find.text('ระบุชื่อตำแหน่ง'), findsOneWidget);
    expect(find.text('เลือกตำแหน่งบนแผนที่'), findsOneWidget);
    expect(find.text('ยังไม่ได้เลือกพิกัด'), findsOneWidget);
    await tester.tap(find.byTooltip('เพิ่มรายการ'));
    await tester.pumpAndSettle();
    expect(find.text('ชั้นที่ (ถ้ามี, ไม่เกิน 50 ชั้น)'), findsOneWidget);
    expect(find.text('เลขห้อง (ถ้ามี)'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('ชื่ออุปกรณ์ที่พัง'), findsNWidgets(2));
    expect(find.text('ข้อมูลเพิ่มเติม'), findsNWidgets(2));
    expect(find.text('เพิ่มรูปถ่าย'), findsNWidgets(2));
    expect(find.text('รายการที่ 2'), findsOneWidget);
  });

  testWidgets('User drawer shows the database UID and role', (tester) async {
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    TemporaryAccountSession.instance.setFromResponse({
      'id': '79f01ec0-1234-4321-9321-123456789abc',
      'username': 'test_user',
      'uid': 'u_1234567890',
      'firstname': 'Test',
      'lastname': 'User',
      'role': 'User',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });

    await tester.pumpWidget(const MaterialApp(home: Layout()));
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    expect(find.text('UID: u_1234567890'), findsOneWidget);
    expect(find.text('Role: User'), findsOneWidget);
    expect(
      find.text('UID: 79f01ec0-1234-4321-9321-123456789abc'),
      findsNothing,
    );
    TemporaryAccountSession.instance.clear();
  });

  testWidgets('Unsign role gets public ticket monitor navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'Unsign')),
    );

    expect(find.text('ค้นหา TicketId'), findsOneWidget);
    expect(find.text('ยังไม่ได้เชื่อมต่อ Supabase'), findsOneWidget);
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    expect(find.textContaining('UID:'), findsNothing);
    expect(find.text('ติดตามงานซ่อม'), findsOneWidget);
    expect(find.text('หน้าหลัก'), findsOneWidget);
    expect(find.text('แจ้งซ่อม'), findsNothing);
  });

  testWidgets(
    'Google sign-in dialog is the only user registration entry point',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Layout(roleOverride: 'Unsign')),
      );

      await tester.tap(find.byTooltip('เข้าสู่ระบบ'));
      await tester.pumpAndSettle();
      expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
      expect(find.text('รหัสผ่าน'), findsNothing);
      expect(find.text('ยังไม่มีบัญชี? สมัครสมาชิก'), findsNothing);
      expect(find.text('สมัครสมาชิก KUFixIT'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    },
  );

  testWidgets('staff login form is reachable from the login dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'Unsign')),
    );

    await tester.tap(find.byTooltip('เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เข้าสู่ระบบช่างและเจ้าหน้าที่ระดับสูง'));
    await tester.pumpAndSettle();

    expect(find.text('ชื่อผู้ใช้'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsOneWidget);
    expect(
      find.text('เข้าสู่ระบบช่างและเจ้าหน้าที่ระดับสูง'),
      findsNWidgets(2),
    );
  });

  testWidgets('personal info page shows display name and prefixed UID', (
    tester,
  ) async {
    final account = TemporaryAccount(
      id: '1234567890',
      username: 'test_user',
      uid: 'u_1234567890',
      firstName: 'Ada',
      lastName: 'Lovelace',
      role: 'User',
      accessToken: 'signed-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(home: PersonalInfoPage(temporaryAccount: account)),
    );

    expect(find.text('ข้อมูลส่วนตัว'), findsOneWidget);
    expect(find.text('รูปโปรไฟล์ปัจจุบัน'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('ชื่อที่แสดง'), findsOneWidget);
    expect(find.text('ชื่อจริง'), findsNothing);
    expect(find.text('นามสกุล'), findsNothing);
    expect(find.text('ชื่อบัญชี'), findsNothing);
    expect(find.text('อีเมลล์'), findsNothing);
    expect(find.text('บทบาท'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('เลขบัญชี'), findsOneWidget);
    expect(find.text('u_1234567890'), findsOneWidget);
    expect(find.text('แก้ไขข้อมูล'), findsOneWidget);
    expect(find.text('บันทึกข้อมูล'), findsNothing);
    expect(find.text('เลขบัญชี'), findsOneWidget);
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsNothing);

    await tester.ensureVisible(find.text('แก้ไขข้อมูล'));
    await tester.tap(find.text('แก้ไขข้อมูล'));
    await tester.pumpAndSettle();
    expect(find.text('ชื่อที่แสดง'), findsOneWidget);
    expect(find.text('เลขบัญชี'), findsOneWidget);
    expect(find.text('นามสกุล'), findsNothing);
    expect(find.text('ชื่อบัญชี'), findsNothing);
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsNothing);
    expect(find.text('รหัสผ่านใหม่ (เว้นว่างถ้าไม่เปลี่ยน)'), findsNothing);
    expect(find.text('ยืนยันรหัสผ่านใหม่'), findsNothing);
    expect(find.text('12/80'), findsOneWidget);
    expect(
      find.text('แตะรูปเพื่อเปลี่ยนรูปโปรไฟล์ (ไม่เกิน 2 MB)'),
      findsOneWidget,
    );
    expect(find.text('บันทึกข้อมูล'), findsOneWidget);

    await tester.ensureVisible(find.text('ยกเลิก'));
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.text('แก้ไขข้อมูล'), findsOneWidget);
    expect(find.text('บันทึกข้อมูล'), findsNothing);

    await tester.ensureVisible(find.text('แก้ไขข้อมูล'));
    await tester.tap(find.text('แก้ไขข้อมูล'));
    await tester.pumpAndSettle();
    final displayNameField = find.byType(TextFormField).first;
    await tester.enterText(displayNameField, 'Updated Display Name');
    await tester.pumpAndSettle();
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsNothing);
    expect(find.text('ยืนยันรหัสผ่านใหม่'), findsNothing);
  });

  testWidgets('reopening the drawer while it closes keeps the page visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'Unsign')),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('หน้าหลัก'));

    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('เปิดเมนู'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(Layout), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('ค้นหา TicketId'), findsOneWidget);
  });

  testWidgets('database connection error page retries on button press', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DatabaseConnectionErrorPage(
          errorMessage: 'Connection timed out',
          onRetry: () => retried = true,
          isRetrying: false,
        ),
      ),
    );

    expect(find.text('Connection timed out'), findsOneWidget);
    await tester.tap(find.text('ลองอีกครั้ง'));
    expect(retried, isTrue);
  });
}
