import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobileproject/auth/temporary_account_session.dart';
import 'package:mobileproject/database/realtime_invalidation.dart';
import 'package:mobileproject/gui/workList.dart';

class FakeImagePicker extends Fake implements ImagePicker {
  FakeImagePicker({this.imageToPick, this.lostDataResponse});

  XFile? imageToPick;
  LostDataResponse? lostDataResponse;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return imageToPick;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return lostDataResponse ?? LostDataResponse.empty();
  }
}

void main() {
  final validImageBytes = img.encodePng(img.Image(width: 10, height: 10));

  setUp(() {
    TemporaryAccountSession.instance.setFromResponse({
      'id': 'tech1',
      'username': 'techteam',
      'firstname': 'Technician',
      'lastname': 'One',
      'isSystemAccount': true,
      'role': 'Technician',
      'accessToken': 'test-token',
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
    });
  });

  tearDown(TemporaryAccountSession.instance.clear);

  WorkTicket createSampleTicket({
    String ticketId = '6262313107',
    String status = 'pending',
  }) {
    return WorkTicket(
      ticketId: ticketId,
      building: '1',
      area: 'Central',
      floor: '2',
      room: '201',
      latitude: 13.12,
      longitude: 100.91,
      status: status,
      devices: const [
        WorkDevice(
          deviceId: 1,
          rowIndex: 1,
          name: 'Air Conditioner',
          description: 'Not cooling',
        ),
      ],
      report: null,
    );
  }

  testWidgets(
    'Realtime invalidation performs silent refresh and preserves form draft',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final invalidations = StreamController<RealtimeInvalidationDomain>.broadcast();
      final sampleTicket = createSampleTicket();
      var fetchCallCount = 0;

      final fakePicker = FakeImagePicker(
        imageToPick: XFile.fromData(
          validImageBytes,
          path: 'result.png',
          name: 'result.png',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkList(
              fetchTickets: () async {
                fetchCallCount++;
                return [sampleTicket];
              },
              imagePicker: fakePicker,
              invalidations: invalidations.stream,
            ),
          ),
        ),
      );

      // Initial loading completes
      await tester.pumpAndSettle();
      expect(fetchCallCount, 1);
      expect(find.text('Ticket 6262313107'), findsOneWidget);
      expect(find.text('Air Conditioner · Not cooling'), findsOneWidget);

      // 1. Select outcome = "ซ่อมสำเร็จ"
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ซ่อมสำเร็จ').last);
      await tester.pumpAndSettle();

      // 2. Attach photo
      expect(find.text('แนบรูปผลลัพธ์ *'), findsOneWidget);
      await tester.tap(find.text('แนบรูปผลลัพธ์ *'));
      await tester.pumpAndSettle();
      expect(find.text('result.png'), findsOneWidget);

      // 3. Type comment
      final commentField = find.byType(TextField);
      expect(commentField, findsOneWidget);
      await tester.enterText(commentField, 'ซ่อมแอร์เสร็จเรียบร้อย เย็นฉ่ำ');
      await tester.pumpAndSettle();

      // Verify state before invalidation
      expect(find.text('ซ่อมสำเร็จ'), findsOneWidget);
      expect(find.text('result.png'), findsOneWidget);
      expect(find.text('ซ่อมแอร์เสร็จเรียบร้อย เย็นฉ่ำ'), findsOneWidget);

      // 4. Trigger Realtime Invalidation
      invalidations.add(RealtimeInvalidationDomain.tickets);

      // Advance past debounce (400ms)
      await tester.pump(const Duration(milliseconds: 450));
      // Settle the fetch
      await tester.pumpAndSettle();

      expect(fetchCallCount, 2);

      // 5. Verify that all draft data and photo are completely preserved!
      expect(find.text('Ticket 6262313107'), findsOneWidget);
      expect(find.text('ซ่อมสำเร็จ'), findsOneWidget);
      expect(find.text('result.png'), findsOneWidget);
      expect(find.text('ซ่อมแอร์เสร็จเรียบร้อย เย็นฉ่ำ'), findsOneWidget);

      await invalidations.close();
    },
  );

  testWidgets(
    'ImagePicker lost data recovery restores photo when activity was destroyed',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final sampleTicket = createSampleTicket();
      final fakePicker = FakeImagePicker(
        lostDataResponse: LostDataResponse(
          file: XFile.fromData(
            validImageBytes,
            path: 'recovered.png',
            name: 'recovered.png',
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkList(
              fetchTickets: () async => [sampleTicket],
              imagePicker: fakePicker,
            ),
          ),
        ),
      );

      // Initial pump: retrieveLostData runs in initState
      await tester.pumpAndSettle();

      // Now set outcome to "ซ่อมสำเร็จ" to show photo section
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ซ่อมสำเร็จ').last);
      await tester.pumpAndSettle();

      // The recovered photo is restored and displayed
      expect(find.text('recovered.png'), findsOneWidget);
    },
  );

  testWidgets(
    'Draft is retained if submission fails, allowing technician to retry',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final sampleTicket = createSampleTicket();
      var submitAttempts = 0;

      final fakePicker = FakeImagePicker(
        imageToPick: XFile.fromData(
          validImageBytes,
          path: 'proof.png',
          name: 'proof.png',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkList(
              fetchTickets: () async => [sampleTicket],
              submitReport: (draft) async {
                submitAttempts++;
                throw Exception('Network disconnected');
              },
              imagePicker: fakePicker,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Fill in outcome and photo
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ซ่อมสำเร็จ').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('แนบรูปผลลัพธ์ *'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ข้อความทดสอบ');
      await tester.pumpAndSettle();

      // Tap submit
      await tester.tap(find.text('ส่งงาน'));
      await tester.pumpAndSettle();

      expect(submitAttempts, 1);
      expect(find.textContaining('ส่งรายงานไม่สำเร็จ'), findsOneWidget);

      // Form data and photo are STILL preserved for retry
      expect(find.text('proof.png'), findsOneWidget);
      expect(find.text('ข้อความทดสอบ'), findsOneWidget);
      expect(find.text('ซ่อมสำเร็จ'), findsOneWidget);
    },
  );
}

