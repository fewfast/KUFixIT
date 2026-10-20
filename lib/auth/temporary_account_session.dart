import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'session_storage.dart';

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


  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'uid': uid,
        'accessUntil': accessUntil != null
            ? accessUntil!.millisecondsSinceEpoch ~/ 1000
            : null,
        'accessRangeStart': accessRangeStart,
        'accessRangeEnd': accessRangeEnd,
        'firstname': firstName,
        'lastname': lastName,
        'displayname': googleDisplayName,
        'hasNationalId': hasNationalId,
        'isSystemAccount': isSystemAccount,
        'role': role,
        'accessToken': accessToken,
        'expiresAt': expiresAt.millisecondsSinceEpoch ~/ 1000,
      };

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
  TemporaryAccountSession._() {
    _restoreFromStorage();
  }

  static final instance = TemporaryAccountSession._();
  static const _storageKey = 'kufixit_temporary_session';

  TemporaryAccount? _account;
  Timer? _expiryTimer;

  TemporaryAccount? get account {
    final account = _account;
    if (account == null || !account.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    return account;
  }

  void _restoreFromStorage() {
    try {
      final raw = BrowserSessionStorage.instance.read(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw);
      final account = TemporaryAccount.fromResponse(json);
      _account = account;
      final duration = account.expiresAt.difference(DateTime.now());
      _expiryTimer = Timer(duration, clear);
    } catch (_) {
      BrowserSessionStorage.instance.remove(_storageKey);
      _account = null;
    }
  }

  void setFromResponse(Object? response) {
    final account = TemporaryAccount.fromResponse(response);
    _expiryTimer?.cancel();
    _account = account;
    final duration = _account!.expiresAt.difference(DateTime.now());
    _expiryTimer = Timer(duration, clear);
    try {
      BrowserSessionStorage.instance.save(
        _storageKey,
        jsonEncode(_account!.toJson()),
      );
    } catch (_) {}
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
    try {
      BrowserSessionStorage.instance.save(
        _storageKey,
        jsonEncode(_account!.toJson()),
      );
    } catch (_) {}
    notifyListeners();
  }

  void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    try {
      BrowserSessionStorage.instance.remove(_storageKey);
    } catch (_) {}
    if (_account == null) return;
    _account = null;
    notifyListeners();
  }
}
