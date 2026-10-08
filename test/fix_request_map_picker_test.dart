import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/fixRequest.dart';

void main() {
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
