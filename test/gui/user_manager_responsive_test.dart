import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/auth/temporary_account_session.dart';
import 'package:mobileproject/gui/userManager.dart';

void main() {
  tearDown(TemporaryAccountSession.instance.clear);

  for (final role in ['Admin', 'SuperAdmin']) {
    testWidgets('$role user management fits a narrow phone viewport', (
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
        'role': role,
        'accessToken': 'signed-token',
        'expiresAt':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserManagerPage(
              invokeOverride: (action, body) async => switch (action) {
                'list-users' => {
                  'users': [
                    {
                      'uid': '1234567890',
                      'created_at': '2026-10-19T12:00:00Z',
                      'displayName': 'ผู้ใช้ทดสอบ',
                      'role': 'User',
                      'status': 'active',
                    },
                  ],
                },
                'list-requests' => {'requests': <Object>[]},
                _ => <String, dynamic>{},
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('จัดการผู้ใช้'), findsOneWidget);
      expect(find.text('UID: 1234567890'), findsOneWidget);
      expect(find.text('ชื่อที่แสดง'), findsOneWidget);
      if (role == 'SuperAdmin') {
        expect(find.text('บทบาท'), findsOneWidget);
        expect(find.text('สถานะ'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      } else {
        expect(find.text('สถานะ: active'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      }
      TemporaryAccountSession.instance.clear();
    });
  }
}
