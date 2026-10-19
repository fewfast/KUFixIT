import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/technician_report_rules.dart';

void main() {
  group('validateTechnicianReport', () {
    test('requires a result for every device', () {
      expect(
        validateTechnicianReport(
          outcomes: [true, null],
          hasPhoto: [true, false],
          comment: '',
        ),
        'กรุณาระบุผลของอุปกรณ์ทุกรายการ',
      );
    });

    test('requires one photo for each successful device', () {
      expect(
        validateTechnicianReport(
          outcomes: [true, true],
          hasPhoto: [true, false],
          comment: '',
        ),
        'อุปกรณ์ที่ซ่อมสำเร็จต้องแนบรูปผลลัพธ์หนึ่งรูป',
      );
    });

    test('rejects a photo for an unsuccessful device', () {
      expect(
        validateTechnicianReport(
          outcomes: [false],
          hasPhoto: [true],
          comment: 'ทำไม่ทัน',
        ),
        'อุปกรณ์ที่ไม่สำเร็จไม่ควรมีรูปผลลัพธ์',
      );
    });

    test('requires comment for a mixed result', () {
      expect(
        validateTechnicianReport(
          outcomes: [true, false],
          hasPhoto: [true, false],
          comment: '  ',
        ),
        'กรุณาระบุความคิดเห็นสำหรับอุปกรณ์ที่ซ่อมไม่สำเร็จ',
      );
    });

    test('allows all-failure without a comment and fixes timeout comment', () {
      expect(
        validateTechnicianReport(
          outcomes: [false, false],
          hasPhoto: [false, false],
          comment: '',
        ),
        isNull,
      );
      expect(
        effectiveTechnicianReportComment(
          outcomes: [false, false],
          comment: 'custom',
        ),
        'ซ่อมไม่สำเร็จ',
      );
    });

    test('allows all-success results without a comment', () {
      expect(
        validateTechnicianReport(
          outcomes: [true, true],
          hasPhoto: [true, true],
          comment: '',
        ),
        isNull,
      );
    });
  });
}
