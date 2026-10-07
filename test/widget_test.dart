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
    await tester.tap(find.text('ยังไม่มีบัญชี? สมัครสมาชิก'));
    await tester.pumpAndSettle();

    expect(find.text('สมัครสมาชิก KUFixIT'), findsOneWidget);
    expect(find.text('ชื่อจริง'), findsOneWidget);
    expect(find.text('นามสกุล'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsOneWidget);
    expect(find.text('สร้างบัญชี'), findsOneWidget);
    final roleDropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(roleDropdown);
    await tester.tap(roleDropdown);
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);
    await tester.tap(find.text('SuperAdmin'));
    await tester.pumpAndSettle();
    expect(find.text('SuperAdmin'), findsOneWidget);
  });

  testWidgets('personal info page shows the temporary account names', (
    tester,
  ) async {
    final account = TemporaryAccount(
      id: '1234567890',
      username: 'test_user',
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
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Lovelace'), findsOneWidget);
    expect(find.text('ชื่อบัญชี'), findsOneWidget);
    expect(find.text('อีเมลล์'), findsNothing);
    expect(find.text('บทบาท'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('เลขบัญชี'), findsOneWidget);
    expect(find.text('1234567890'), findsOneWidget);
    expect(find.text('แก้ไขข้อมูล'), findsOneWidget);
    expect(find.text('บันทึกข้อมูล'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField && widget.controller?.text == 'test_user',
      ),
      findsNothing,
    );
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsNothing);

    await tester.ensureVisible(find.text('แก้ไขข้อมูล'));
    await tester.tap(find.text('แก้ไขข้อมูล'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField && widget.controller?.text == 'test_user',
      ),
      findsOneWidget,
    );
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsNothing);
    expect(find.text('รหัสผ่านใหม่ (เว้นว่างถ้าไม่เปลี่ยน)'), findsOneWidget);
    expect(find.text('ยืนยันรหัสผ่านใหม่'), findsNothing);
    expect(find.text('3/80'), findsOneWidget);
    expect(find.text('8/80'), findsOneWidget);
    expect(find.text('9/30'), findsOneWidget);
    expect(
      find.text('แตะรูปเพื่อเปลี่ยนรูปโปรไฟล์ (ไม่เกิน 5 MB)'),
      findsOneWidget,
    );
    expect(find.text('บันทึกข้อมูล'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'รหัสผ่านใหม่ (เว้นว่างถ้าไม่เปลี่ยน)',
      ),
      'StrongPass1!',
    );
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันรหัสผ่านใหม่'), findsOneWidget);
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsOneWidget);
    expect(find.text('ตรวจสอบรหัสผ่าน'), findsOneWidget);
    expect(find.text('อักขระอย่างน้อย 8 ตัว (12/128)'), findsOneWidget);
    expect(find.text('ตัวเลขอย่างน้อย 1 ตัวเลข'), findsOneWidget);
    expect(find.text('ตัวอักษรพิมพ์เล็กอย่างน้อย 1 ตัวอักษร'), findsOneWidget);
    expect(find.text('ตัวอักษรพิมพ์ใหญ่อย่างน้อย 1 ตัวอักษร'), findsOneWidget);
    expect(find.text('ตัวอักษรพิเศษอย่างน้อย 1 ตัวอักษร'), findsOneWidget);
    expect(find.text('0/128'), findsNothing);
    expect(find.text('0/13'), findsNothing);

    await tester.ensureVisible(find.text('ยกเลิก'));
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.text('แก้ไขข้อมูล'), findsOneWidget);
    expect(find.text('บันทึกข้อมูล'), findsNothing);

    await tester.ensureVisible(find.text('แก้ไขข้อมูล'));
    await tester.tap(find.text('แก้ไขข้อมูล'));
    await tester.pumpAndSettle();
    final usernameField = find.byType(TextFormField).at(2);
    await tester.enterText(usernameField, 'updated_user');
    await tester.pumpAndSettle();
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsOneWidget);
    expect(find.text('ยืนยันรหัสผ่านใหม่'), findsNothing);

    await tester.enterText(usernameField, 'test_user');
    await tester.pumpAndSettle();
    expect(find.text('เลขบัตรประชาชนเพื่อยืนยัน'), findsNothing);
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
