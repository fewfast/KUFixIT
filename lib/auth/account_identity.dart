bool isValidUsername(String username) {
  return RegExp(r'^[a-zA-Z0-9_-]{3,30}$').hasMatch(username);
}

Map<String, bool> passwordRequirementStatus(String password) {
  return {
    'อักขระอย่างน้อย 8 ตัว': password.length >= 8,
    'ตัวเลขอย่างน้อย 1 ตัวเลข': RegExp(r'[0-9]').hasMatch(password),
    'ตัวอักษรพิมพ์เล็กอย่างน้อย 1 ตัวอักษร': RegExp(r'[a-z]')
        .hasMatch(password),
    'ตัวอักษรพิมพ์ใหญ่อย่างน้อย 1 ตัวอักษร': RegExp(r'[A-Z]')
        .hasMatch(password),
    'ตัวอักษรพิเศษอย่างน้อย 1 ตัวอักษร': RegExp(
      r'[^a-zA-Z0-9]',
    ).hasMatch(password),
  };
}

bool isStrongPassword(String password) {
  return password.length <= 128 &&
      passwordRequirementStatus(password).values.every((isMet) => isMet);
}
