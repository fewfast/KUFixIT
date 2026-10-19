/// Validates the technician's per-device result before it is sent to the API.
String? validateTechnicianReport({
  required List<bool?> outcomes,
  required List<bool> hasPhoto,
  required String comment,
}) {
  if (outcomes.length != hasPhoto.length || outcomes.isEmpty) {
    return 'ไม่พบรายการอุปกรณ์ที่รายงาน';
  }
  if (outcomes.any((outcome) => outcome == null)) {
    return 'กรุณาระบุผลของอุปกรณ์ทุกรายการ';
  }
  for (var index = 0; index < outcomes.length; index++) {
    if (outcomes[index]! && !hasPhoto[index]) {
      return 'อุปกรณ์ที่ซ่อมสำเร็จต้องแนบรูปผลลัพธ์หนึ่งรูป';
    }
    if (!outcomes[index]! && hasPhoto[index]) {
      return 'อุปกรณ์ที่ไม่สำเร็จไม่ควรมีรูปผลลัพธ์';
    }
  }
  final hasSuccess = outcomes.contains(true);
  final hasFailure = outcomes.contains(false);
  if (hasSuccess && hasFailure && comment.trim().isEmpty) {
    return 'กรุณาระบุความคิดเห็นสำหรับอุปกรณ์ที่ซ่อมไม่สำเร็จ';
  }
  if (comment.length > 5000) return 'ความคิดเห็นต้องไม่เกิน 5,000 ตัวอักษร';
  return null;
}

String effectiveTechnicianReportComment({
  required List<bool> outcomes,
  required String comment,
}) => outcomes.every((outcome) => !outcome) ? 'ซ่อมไม่สำเร็จ' : comment.trim();
