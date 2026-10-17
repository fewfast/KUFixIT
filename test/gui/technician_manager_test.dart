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

    expect(find.text('ชื่อช่าง'), findsOneWidget);
    expect(find.text('username ช่าง'), findsOneWidget);
    expect(find.text('ข้อมูลช่าง *'), findsOneWidget);
    expect(find.text('จำเป็นต้องกรอก'), findsOneWidget);
    expect(find.text('สร้างบัญชีช่าง'), findsOneWidget);
    expect(find.text('เลือกทีมช่าง'), findsNothing);
    expect(find.text('สถานะ'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), 'ช่างทดสอบ');
    await tester.enterText(find.byType(TextField).at(1), 'test_tech');
    await tester.ensureVisible(find.text('สร้างบัญชีช่าง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สร้างบัญชีช่าง'));
    await tester.pump();
    expect(find.text('กรุณากรอกข้อมูลช่าง'), findsOneWidget);
    TemporaryAccountSession.instance.clear();
  });
}
