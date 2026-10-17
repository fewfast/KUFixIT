import 'dart:async';

import 'package:flutter/foundation.dart';

class TemporaryAccount {
  const TemporaryAccount({
    required this.id,
    required this.username,
    this.uid,
    this.accessUntil,
    this.accessRangeStart,
    this.accessRangeEnd,
    required this.firstName,
    required this.lastName,
    this.googleDisplayName,
    this.hasNationalId = true,
    this.isSystemAccount = false,
    required this.role,
    required this.accessToken,
    required this.expiresAt,
  });

  final String id;
  final String username;
  final String? uid;
  final DateTime? accessUntil;
  final String? accessRangeStart;
  final String? accessRangeEnd;
  final String firstName;
  final String lastName;
  final String? googleDisplayName;
  final bool hasNationalId;
  final bool isSystemAccount;
  final String role;
  final String accessToken;
  final DateTime expiresAt;

  String get displayName {
    final name = googleDisplayName?.trim();
    return name == null || name.isEmpty ? '$firstName $lastName' : name;
  }

  factory TemporaryAccount.fromResponse(Object? response) {
    if (response is! Map) {
      throw const FormatException('Invalid temporary session response.');
    }
    final data = Map<String, Object?>.from(response);
    final id = data['id'];
    final username = data['username'];
    final rawUid = data['uid'];
    final rawAccessUntil = data['accessUntil'];
    final accessRangeStart = data['accessRangeStart'];
    final accessRangeEnd = data['accessRangeEnd'];
    final firstName = data['firstname'];
    final lastName = data['lastname'];
    final googleDisplayName = data['displayname'];
    final hasNationalId = data['hasNationalId'];
    final isSystemAccount = data['isSystemAccount'];
    final role = data['role'];
    final accessToken = data['accessToken'];
    final expiresAt = data['expiresAt'];
    final uid = switch (rawUid) {
      num value when value.isFinite && value == value.truncateToDouble() =>
        value.toInt().toString(),
      String value
          when RegExp(
            r'^(?:\d{10}|[ut]_(?:\d{10}|[0-9a-f]{32}))$',
            caseSensitive: false,
          ).hasMatch(value) =>
        value,
      _ => null,
    };

    if (id == null ||
        username is! String ||
        (rawUid != null &&
            (uid == null ||
                (RegExp(r'^\d+$').hasMatch(uid) &&
                    (uid.length != 10 || int.tryParse(uid) == null)))) ||
        (rawAccessUntil != null && rawAccessUntil is! int) ||
        (accessRangeStart != null &&
            (accessRangeStart is! String ||
                DateTime.tryParse(accessRangeStart) == null)) ||
        (accessRangeEnd != null &&
            (accessRangeEnd is! String ||
                DateTime.tryParse(accessRangeEnd) == null)) ||
        ((accessRangeStart == null) != (accessRangeEnd == null)) ||
        (accessRangeStart is String &&
            accessRangeEnd is String &&
            accessRangeStart.compareTo(accessRangeEnd) > 0) ||
        firstName is! String ||
        lastName is! String ||
        (googleDisplayName != null && googleDisplayName is! String) ||
        (hasNationalId != null && hasNationalId is! bool) ||
        (isSystemAccount != null && isSystemAccount is! bool) ||
        role is! String ||
        accessToken is! String ||
        expiresAt is! int ||
        !{'User', 'Admin', 'SuperAdmin', 'Technician'}.contains(role)) {
      throw const FormatException('Invalid temporary session response.');
    }
    if (isSystemAccount != true &&
        (role == 'User' || role == 'Admin') &&
        uid == null) {
      throw const FormatException(
        'Temporary session is missing the account UID.',
      );
    }

    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    if (!expiry.isAfter(DateTime.now())) {
      throw const FormatException('Temporary session has expired.');
    }

    return TemporaryAccount(
      id: id.toString(),
      username: username,
      uid: uid,
      accessUntil: rawAccessUntil is int
          ? DateTime.fromMillisecondsSinceEpoch(rawAccessUntil * 1000)
          : null,
      accessRangeStart: accessRangeStart as String?,
      accessRangeEnd: accessRangeEnd as String?,
      firstName: firstName,
      lastName: lastName,
      googleDisplayName: googleDisplayName is String ? googleDisplayName : null,
      hasNationalId: hasNationalId is bool ? hasNationalId : true,
      isSystemAccount: isSystemAccount is bool ? isSystemAccount : false,
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

  void updateProfile({required String displayName}) {
    final account = this.account;
    if (account == null) return;

    _account = TemporaryAccount(
      id: account.id,
      username: account.username,
      uid: account.uid,
      accessUntil: account.accessUntil,
      accessRangeStart: account.accessRangeStart,
      accessRangeEnd: account.accessRangeEnd,
      firstName: displayName,
      lastName: '',
      googleDisplayName: displayName.trim(),
      hasNationalId: account.hasNationalId,
      isSystemAccount: account.isSystemAccount,
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
