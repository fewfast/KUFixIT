import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/fixRequest.dart';

void main() {
  testWidgets('scrolls to the first missing repair field on submit', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FixRequestPage())),
    );

    final buildingField = find.descendant(
      of: find.byType(Autocomplete<String>),
      matching: find.byType(TextFormField),
    );
    await tester.tap(buildingField);
    await tester.enterText(buildingField, 'อาคาร 1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('อาคาร 1 บริการวิชาการ'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(buildingField).controller!.text,
      'อาคาร 1 บริการวิชาการ',
    );

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ส่งคำร้อง'));
    await tester.tap(find.text('ส่งคำร้อง'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(buildingField).controller!.text,
      'อาคาร 1 บริการวิชาการ',
    );
    final equipmentField = find.widgetWithText(
      TextFormField,
      'ชื่ออุปกรณ์ที่พัง',
    );
    expect(equipmentField, findsOneWidget);
    await tester.ensureVisible(equipmentField);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(equipmentField).dy, greaterThanOrEqualTo(0));
    expect(find.text('กรุณากรอกข้อมูล'), findsOneWidget);
  });

  testWidgets('requires a location name when other building is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FixRequestPage())),
    );

    final buildingField = find.byType(TextFormField).first;
    await tester.tap(buildingField);
    await tester.enterText(buildingField, 'อื่น');
    await tester.pumpAndSettle();
    expect(find.text('อื่นๆ'), findsOneWidget);
    await tester.tap(find.text('อื่นๆ'));
    await tester.pumpAndSettle();

    expect(find.text('ระบุชื่อตำแหน่ง'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ส่งคำร้อง'));
    await tester.tap(find.text('ส่งคำร้อง'));
    await tester.pumpAndSettle();

    expect(find.text('กรุณาระบุชื่อตำแหน่ง'), findsOneWidget);
    expect(find.text('กรุณาเลือกตำแหน่งบนแผนที่'), findsOneWidget);
  });

  testWidgets(
    'floor is capped at 50 and room accepts letters, digits, and hyphens',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FixRequestPage())),
      );

      final floorField = find.widgetWithText(
        TextFormField,
        'ชั้นที่ (ถ้ามี, ไม่เกิน 50 ชั้น)',
      );
      final roomField = find.widgetWithText(TextFormField, 'เลขห้อง (ถ้ามี)');

      await tester.enterText(floorField, 'ชั้น 2');
      await tester.enterText(roomField, 'A203');

      expect(tester.widget<TextFormField>(floorField).controller!.text, '2');
      expect(tester.widget<TextFormField>(roomField).controller!.text, 'A203');
      await tester.enterText(roomField, 'A-203');
      expect(tester.widget<TextFormField>(roomField).controller!.text, 'A-203');

      await tester.enterText(floorField, '51');
      expect(tester.widget<TextFormField>(floorField).controller!.text, '2');
      await tester.enterText(floorField, '50');
      expect(tester.widget<TextFormField>(floorField).controller!.text, '50');

      await tester.enterText(roomField, 'ROOM12345');
      expect(
        tester.widget<TextFormField>(roomField).controller!.text,
        'ROOM1234',
      );

      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      final submitButton = find.text('ส่งคำร้อง');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('กรุณาเลือกอาคารจากรายการ'), findsOneWidget);
      expect(tester.getTopLeft(find.text('อาคาร')).dy, greaterThanOrEqualTo(0));

      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(find.text('กรุณาแนบรูปถ่าย'), findsOneWidget);
    },
  );
}
