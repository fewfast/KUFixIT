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
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    expect(find.text('งานที่ได้รับ'), findsOneWidget);

    await tester.tap(find.text('งานที่ได้รับ'));
    await tester.pumpAndSettle();

    expect(find.text('KUFixIT'), findsOneWidget);
    expect(find.text('รายการงานซ่อมที่ได้รับมอบหมาย'), findsOneWidget);
    expect(find.text('รายการแจ้งซ่อมของฉัน'), findsNothing);
  });

  testWidgets('User role gets request navigation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'User')),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    expect(find.text('แจ้งซ่อม'), findsOneWidget);
    expect(find.text('รายการแจ้งซ่อมของฉัน'), findsOneWidget);
    expect(find.text('จัดการผู้ใช้'), findsNothing);
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
    expect(find.text('ชั้นที่ (ถ้ามี)'), findsOneWidget);
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
    expect(find.text('ชั้นที่ (ถ้ามี)'), findsOneWidget);
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
      'uid': 1234567890,
      'firstname': 'Test',
      'lastname': 'User',
      'role': 'User',
      'accessToken': 'signed-token',
      'expiresAt': expiresAt,
    });

    await tester.pumpWidget(const MaterialApp(home: Layout()));
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    expect(find.text('UID: 1234567890'), findsOneWidget);
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

    expect(
      find.text('สถานะงานซ่อมจะแสดงที่นี่เมื่อเชื่อมต่อข้อมูลแล้ว'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();

    expect(find.textContaining('UID:'), findsNothing);
    expect(find.text('ติดตามงานซ่อม'), findsNWidgets(2));
    expect(find.text('หน้าหลัก'), findsNothing);
    expect(find.text('แจ้งซ่อม'), findsNothing);
  });

  testWidgets('registration page is reachable from the login dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Layout(roleOverride: 'Unsign')),
    );

    await tester.tap(find.byTooltip('เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsNothing);
    await tester.tap(find.text('ยังไม่มีบัญชี? สมัครสมาชิก'));
    await tester.pumpAndSettle();

    expect(find.text('สมัครสมาชิก KUFixIT'), findsOneWidget);
    expect(find.text('สมัครด้วย Google'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('รหัสผ่าน'), findsNothing);
    expect(find.text('สร้างบัญชี'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

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

  testWidgets('personal info page shows display name and 10-digit UID', (
    tester,
  ) async {
    final account = TemporaryAccount(
      id: '1234567890',
      username: 'test_user',
      uid: 1234567890,
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
    expect(find.text('1234567890'), findsOneWidget);
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
      find.text('แตะรูปเพื่อเปลี่ยนรูปโปรไฟล์ (ไม่เกิน 5 MB)'),
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
    await tester.tap(find.text('ติดตามงานซ่อม').last);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('เปิดเมนู'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(Layout), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.text('สถานะงานซ่อมจะแสดงที่นี่เมื่อเชื่อมต่อข้อมูลแล้ว'),
      findsOneWidget,
    );
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
