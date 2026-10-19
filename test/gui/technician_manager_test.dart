import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/auth/temporary_account_session.dart';
import 'package:mobileproject/gui/technicianManager.dart';

void main() {
  tearDown(TemporaryAccountSession.instance.clear);

  testWidgets('Admin can enter technician details and usernames', (
    tester,
  ) async {
    TemporaryAccountSession.instance.setFromResponse({
      'id': 'admin1',
      'username': 'admin1',
      'firstname': 'Admin',
      'lastname': '',
      'isSystemAccount': true,
      'role': 'Admin',
      'accessToken': 'signed-token',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TechnicianManagerPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('ชื่อทีมช่าง'), findsOneWidget);
    expect(find.text('username'), findsOneWidget);
    expect(find.text('ข้อมูลช่าง'), findsOneWidget);
    expect(find.text('จำเป็นต้องกรอก'), findsNWidgets(2));
    expect(find.text('สร้างบัญชีช่าง'), findsOneWidget);
    expect(find.text('เลือกทีมช่าง'), findsOneWidget);
    expect(find.text('รายการงานตามทีมช่าง'), findsOneWidget);
    expect(
      tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
          .enableFilter,
      isTrue,
    );
    expect(find.text('สถานะ'), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'username',
            ),
          )
          .maxLength,
      10,
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'ชื่อทีมช่าง',
      ),
      'ช่างทดสอบ',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'username',
      ),
      'test_tech',
    );
    await tester.ensureVisible(find.text('สร้างบัญชีช่าง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สร้างบัญชีช่าง'));
    await tester.pump();
    expect(find.text('กรุณากรอกข้อมูลช่าง'), findsOneWidget);
    TemporaryAccountSession.instance.clear();
  });

  testWidgets('technician manager fits a narrow phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TemporaryAccountSession.instance.setFromResponse({
      'id': 'admin1',
      'username': 'admin1',
      'firstname': 'Admin',
      'lastname': '',
      'isSystemAccount': true,
      'role': 'Admin',
      'accessToken': 'signed-token',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TechnicianManagerPage(
            invokeOverride: (action, body) async => {
              if (action == 'list-technicians')
                'technicians': [
                  {
                    'uid': 't_1234567890',
                    'created_at': '2026-10-19T12:00:00Z',
                    'teamName': 'ทีมทดสอบ 1',
                    'username': 'tech_one',
                    'comment': 'รายละเอียดทีมหนึ่ง',
                    'password': 'test-only',
                    'start_time': <String>[],
                    'end_time': <String>[],
                  },
                  {
                    'uid': 't_1234567891',
                    'created_at': '2026-10-19T12:00:00Z',
                    'teamName': 'ทีมทดสอบ 2',
                    'username': 'tech_two',
                    'comment': 'รายละเอียดทีมสอง',
                    'password': 'test-only',
                    'start_time': <String>[],
                    'end_time': <String>[],
                  },
                ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('รายการช่างทั้งหมด'), findsOneWidget);
    expect(find.text('ทีมทดสอบ 1'), findsOneWidget);
    expect(find.text('ทีมทดสอบ 2'), findsNothing);
    expect(find.textContaining('แสดง 1–1 จาก 2 ทีม'), findsOneWidget);
    TemporaryAccountSession.instance.clear();
  });
}
