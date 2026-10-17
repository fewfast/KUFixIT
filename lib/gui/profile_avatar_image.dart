import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List normalizeProfileAvatar(List<int> bytes) {
  final decoded = img.decodeImage(Uint8List.fromList(bytes));
  if (decoded == null) {
    throw const FormatException('ไฟล์ที่เลือกไม่ใช่รูปภาพที่ถูกต้อง');
  }

  final oriented = img.bakeOrientation(decoded);
  final resized = oriented.width > 1024 || oriented.height > 1024
      ? oriented.width >= oriented.height
            ? img.copyResize(oriented, width: 1024)
            : img.copyResize(oriented, height: 1024)
      : oriented;
  return img.encodeJpg(resized, quality: 85);
}
