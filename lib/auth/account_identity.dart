bool isValidUsername(String username) {
  return RegExp(r'^[a-zA-Z0-9_-]{3,30}$').hasMatch(username);
}
