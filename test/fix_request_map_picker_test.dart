import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/fixRequest.dart';

void main() {
  testWidgets('selected building uses its supplied coordinates', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FixRequestPage())),
    );

    final buildingField = find.byType(TextFormField).first;
    await tester.tap(buildingField);
    await tester.enterText(buildingField, 'อาคาร 2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('อาคาร 2 ปฏิบัติการวิศวกรรมศาสตร์').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Latitude: 13.120758  Longitude: 100.920092'),
      findsOneWidget,
    );

    await tester.enterText(buildingField, 'อาคาร 29');
    await tester.pumpAndSettle();
    expect(find.text('อาคาร 29 อาคารปฏิบัติการไฟฟ้าแรงสูง'), findsNothing);
  });

  testWidgets('Windows location picker uses a supported map widget', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    try {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FixRequestPage())),
      );

      await tester.tap(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, 'อื่น');
      await tester.pumpAndSettle();
      await tester.tap(find.text('อื่นๆ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('เลือกตำแหน่งบนแผนที่'));
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('แตะบนแผนที่เพื่อเลือกตำแหน่ง'), findsOneWidget);
      expect(
        tester
            .widget<RichAttributionWidget>(find.byType(RichAttributionWidget))
            .showFlutterMapAttribution,
        isFalse,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
