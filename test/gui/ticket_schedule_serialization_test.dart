import 'package:flutter_test/flutter_test.dart';
import 'package:mobileproject/gui/ticket_schedule_serialization.dart';

void main() {
  test('encodes calendar midnight as the matching Bangkok instant', () {
    expect(
      bangkokDateBoundaryIso8601(DateTime(2026, 10, 22)),
      '2026-10-21T17:00:00.000Z',
    );
  });

  test('uses the calendar components and ignores a supplied time of day', () {
    expect(
      bangkokDateBoundaryIso8601(DateTime(2026, 10, 22, 16, 45)),
      '2026-10-21T17:00:00.000Z',
    );
  });
}
