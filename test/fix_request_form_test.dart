import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/fixRequest.dart';

void main() {
  testWidgets('floor and room accept digits only and a photo is required', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FixRequestPage())),
    );

    final floorField = find.widgetWithText(TextFormField, 'ชั้นที่ (ถ้ามี)');
    final roomField = find.widgetWithText(TextFormField, 'เลขห้อง (ถ้ามี)');

    await tester.enterText(floorField, 'ชั้น 2');
    await tester.enterText(roomField, 'A203');

    expect(tester.widget<TextFormField>(floorField).controller!.text, '2');
    expect(tester.widget<TextFormField>(roomField).controller!.text, '203');

    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    final submitButton = find.text('ส่งคำร้อง');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('กรุณาแนบรูปถ่าย'), findsOneWidget);
  });
}
