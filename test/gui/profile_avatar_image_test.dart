import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobileproject/gui/profile_avatar_image.dart';

void main() {
  test('normalizes selected images to a resized JPEG', () {
    final source = img.encodePng(img.Image(width: 1600, height: 800));

    final normalized = normalizeProfileAvatar(source);
    final decoded = img.decodeImage(normalized);

    expect(normalized.sublist(0, 3), [0xff, 0xd8, 0xff]);
    expect(decoded, isNotNull);
    expect(decoded!.width, 1024);
    expect(decoded.height, 512);
  });

  test('rejects bytes that cannot be decoded as an image', () {
    expect(
      () => normalizeProfileAvatar([0, 1, 2, 3]),
      throwsA(isA<FormatException>()),
    );
  });
}
