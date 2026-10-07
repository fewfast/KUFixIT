import 'dart:async';

import 'package:flutter/foundation.dart';

class TemporaryAccount {
  const TemporaryAccount({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.accessToken,
    required this.expiresAt,
  });

  final String id;
  final String username;
  final String firstName;
  final String lastName;
  final String role;
  final String accessToken;
  final DateTime expiresAt;

  String get displayName => '$firstName $lastName';

  factory TemporaryAccount.fromResponse(Object? response) {
    if (response is! Map) {
      throw const FormatException('Invalid temporary session response.');
    }
    final data = Map<String, Object?>.from(response);
    final id = data['id'];
    final username = data['username'];
    final firstName = data['firstname'];
    final lastName = data['lastname'];
    final role = data['role'];
    final accessToken = data['accessToken'];
    final expiresAt = data['expiresAt'];

    if (id == null ||
        username is! String ||
        firstName is! String ||
        lastName is! String ||
        role is! String ||
        accessToken is! String ||
        expiresAt is! int ||
        !{'User', 'Admin', 'SuperAdmin', 'Technician'}.contains(role)) {
      throw const FormatException('Invalid temporary session response.');
    }

    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    if (!expiry.isAfter(DateTime.now())) {
      throw const FormatException('Temporary session has expired.');
    }

    return TemporaryAccount(
      id: id.toString(),
      username: username,
      firstName: firstName,
      lastName: lastName,
      role: role,
      accessToken: accessToken,
      expiresAt: expiry,
    );
  }
}

class TemporaryAccountSession extends ChangeNotifier {
  TemporaryAccountSession._();

  static final instance = TemporaryAccountSession._();

  TemporaryAccount? _account;
  Timer? _expiryTimer;

  TemporaryAccount? get account {
    final account = _account;
    if (account == null || !account.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    return account;
  }

  void setFromResponse(Object? response) {
    final account = TemporaryAccount.fromResponse(response);
    _expiryTimer?.cancel();
    _account = account;
    final duration = _account!.expiresAt.difference(DateTime.now());
    _expiryTimer = Timer(duration, clear);
    notifyListeners();
  }

  void updateProfile({
    required String firstName,
    required String lastName,
    required String username,
  }) {
    final account = this.account;
    if (account == null) return;

    _account = TemporaryAccount(
      id: account.id,
      username: username,
      firstName: firstName,
      lastName: lastName,
      role: account.role,
      accessToken: account.accessToken,
      expiresAt: account.expiresAt,
    );
    notifyListeners();
  }

  void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (_account == null) return;
    _account = null;
    notifyListeners();
  }
}
