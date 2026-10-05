// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobileproject/gui/database_connection_error_page.dart';
import 'package:mobileproject/gui/layout.dart';

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
    await tester.tap(
      find.byTooltip('เปิดเมนู'),
      warnIfMissed: false,
    );
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
