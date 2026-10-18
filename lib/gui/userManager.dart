// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';

class UserManagerPage extends StatefulWidget {
  const UserManagerPage({super.key});

  @override
  State<UserManagerPage> createState() => _UserManagerPageState();
}

class _UserManagerPageState extends State<UserManagerPage> {
  static const _usersPerPage = 5;

  final _searchController = TextEditingController();
  List<_ManagedUser> _users = [];
  Set<String> _pendingActions = {};
  int _currentPage = 0;
  bool _isLoading = true;
  String? _error;
  final Set<String> _submittingUids = {};

  bool get _isSuperAdmin =>
      TemporaryAccountSession.instance.account?.role == 'SuperAdmin';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _disposeUsers(_users);
    super.dispose();
  }

  void _disposeUsers(List<_ManagedUser> users) {
    for (final user in users) {
      user.displayNameController.dispose();
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    final account = TemporaryAccountSession.instance.account;
    if (account == null ||
        (account.role != 'Admin' && account.role != 'SuperAdmin')) {
      throw Exception('กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลระบบ');
    }
    if (!SupabaseConnection.isInitialized) {
      throw Exception('ยังไม่ได้เชื่อมต่อ Supabase');
    }

    late final Object? responseData;
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'superadmin-users',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {'action': action, ...body},
      );
      responseData = response.data;
    } catch (error) {
      throw Exception(
        functionErrorMessage(error, 'เรียกบริการจัดการผู้ใช้ไม่สำเร็จ'),
      );
    }
    if (responseData is! Map) {
      throw const FormatException('รูปแบบข้อมูลจากระบบจัดการผู้ใช้ไม่ถูกต้อง');
    }
    final data = Map<String, dynamic>.from(responseData);
    if (data['error'] is String) {
      throw Exception(data['error'] as String);
    }
    return data;
  }

  String _errorText(Object error) {
    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 0;
    });
    try {
      final data = await _invoke('list-users');
      final rawUsers = data['users'];
      if (rawUsers is! List) {
        throw const FormatException('ไม่พบรายการผู้ใช้ในข้อมูลตอบกลับ');
      }
      final users = rawUsers.map(_ManagedUser.fromJson).toList(growable: false);
      final pendingActions = _isSuperAdmin
          ? _pendingActionsFromResponse(await _invoke('list-requests'))
          : <String>{};
      if (!mounted) {
        _disposeUsers(users);
        return;
      }
      final previousUsers = _users;
      setState(() {
        _users = users;
        _pendingActions = pendingActions;
        _isLoading = false;
      });
      _disposeUsers(previousUsers);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _errorText(error);
      });
    }
  }

  Set<String> _pendingActionsFromResponse(Map<String, dynamic> response) {
    final rawRequests = response['requests'];
    if (rawRequests is! List) {
      throw const FormatException('ไม่พบรายการคำขอยืนยันในข้อมูลตอบกลับ');
    }

    final pendingActions = <String>{};
    for (final value in rawRequests) {
      if (value is! Map) {
        throw const FormatException('รูปแบบคำขอยืนยันไม่ถูกต้อง');
      }
      final request = Map<String, dynamic>.from(value);
      final uid = request['target_uid'];
      final status = request['status'];
      final requestedRole = request['requested_role'];
      final requestedStatus = request['requested_status'];
      if (uid is! String ||
          status is! String ||
          (requestedRole != null && requestedRole is! String) ||
          (requestedStatus != null && requestedStatus is! String)) {
        throw const FormatException('ข้อมูลคำขอยืนยันไม่ครบถ้วน');
      }
      if (status != 'pending') continue;
      if (requestedRole != null) pendingActions.add('$uid:role');
      if (requestedStatus != null) pendingActions.add('$uid:status');
    }
    return pendingActions;
  }

  List<_ManagedUser> get _filteredUsers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users
        .where((user) {
          return user.uid.toLowerCase().contains(query) ||
              user.createdAt.toLowerCase().contains(query) ||
              user.displayNameController.text.toLowerCase().contains(query) ||
              user.role.toLowerCase().contains(query) ||
              user.status.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Map<String, Object?> _changesFor(_ManagedUser user) {
    final changes = <String, Object?>{};
    final displayName = user.displayNameController.text.trim();
    if (displayName != user.originalDisplayName) {
      changes['displayName'] = displayName;
    }
    if (_isSuperAdmin) {
      if (user.role != user.originalRole) changes['role'] = user.role;
      if (user.status != user.originalStatus) changes['status'] = user.status;
    }
    return changes;
  }

  bool _hasPendingAction(_ManagedUser user) {
    return _hasPendingActionFor(user, _changesFor(user), _pendingActions);
  }

  bool _hasPendingActionFor(
    _ManagedUser user,
    Map<String, Object?> changes,
    Set<String> pendingActions,
  ) {
    return (changes.containsKey('role') &&
            pendingActions.contains('${user.uid}:role')) ||
        (changes.containsKey('status') &&
            pendingActions.contains('${user.uid}:status'));
  }

  Future<void> _submitChange(_ManagedUser user) async {
    final changes = _changesFor(user);
    if (changes.isEmpty) return;
    if (_hasPendingAction(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('มีคำขอรายการนี้รอการยืนยันอยู่แล้ว')),
      );
      return;
    }
    setState(() => _submittingUids.add(user.uid));
    try {
      if (_isSuperAdmin) {
        final latestPendingActions = _pendingActionsFromResponse(
          await _invoke('list-requests'),
        );
        if (!mounted) return;
        setState(() => _pendingActions = latestPendingActions);
        if (_hasPendingActionFor(user, changes, latestPendingActions)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('มีคำขอรายการนี้รอการยืนยันอยู่แล้ว')),
          );
          return;
        }
      }

      final response = await _invoke('submit-change', {
        'uid': user.uid,
        'changes': changes,
      });
      final result = response['result'];
      if (result is! Map || result['status'] is! String) {
        throw const FormatException('ผลการบันทึกข้อมูลผู้ใช้ไม่ถูกต้อง');
      }
      final status = result['status'] as String;
      final displayNameUpdated = result['displayNameUpdated'] == true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !_isSuperAdmin
                ? 'บันทึกชื่อที่แสดงเรียบร้อยแล้ว'
                : status == 'updated'
                ? 'บันทึก displayName แล้ว'
                : displayNameUpdated
                ? 'บันทึก displayName แล้ว ส่วน role/status รอ SuperAdmin อีกคนยืนยัน'
                : 'ส่งคำขอยืนยันแล้ว ต้องรอ SuperAdmin อีกคนอนุมัติ',
          ),
        ),
      );
      await _loadUsers();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorText(error))));
    } finally {
      if (mounted) setState(() => _submittingUids.remove(user.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;
    final pageCount = (users.length / _usersPerPage).ceil();
    final startIndex = _currentPage * _usersPerPage;
    final pageUsers = users.skip(startIndex).take(_usersPerPage);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'จัดการผู้ใช้',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'รีเฟรชรายชื่อผู้ใช้',
                onPressed: _isLoading ? null : _loadUsers,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (!_isSuperAdmin) ...[
            const SizedBox(height: 4),
            const Text('Admin สามารถแก้ไขได้เฉพาะชื่อที่แสดง'),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() => _currentPage = 0),
            decoration: const InputDecoration(
              labelText: 'ค้นหา user',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loadUsers,
                      child: const Text('ลองอีกครั้ง'),
                    ),
                  ],
                ),
              ),
            )
          else if (users.isEmpty)
            const Expanded(child: Center(child: Text('ไม่พบข้อมูลผู้ใช้')))
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final minTableWidth = constraints.maxWidth < 900
                      ? (_isSuperAdmin ? 924.0 : 790.0)
                      : constraints.maxWidth;
                  final tableWidth = constraints.maxWidth < minTableWidth
                      ? minTableWidth
                      : constraints.maxWidth;
                  final columnRatios = _isSuperAdmin
                      ? const [0.14, 0.19, 0.20, 0.13, 0.14, 0.20]
                      : const [0.16, 0.23, 0.25, 0.16, 0.20];
                  var columnIndex = 0;
                  DataColumn column({required String label}) {
                    final index = columnIndex++;
                    return DataColumn(
                      columnWidth: FixedColumnWidth(
                        tableWidth * columnRatios[index],
                      ),
                      headingRowAlignment: MainAxisAlignment.center,
                      label: Center(
                        child: Text(label, textAlign: TextAlign.center),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minTableWidth),
                        child: DataTable(
                          columnSpacing: 18,
                          horizontalMargin: 12,
                          columns: [
                            column(label: 'uid'),
                            column(label: 'เวลาสร้างบัญชี'),
                            column(label: 'ชื่อที่แสดง'),
                            if (_isSuperAdmin) column(label: 'บทบาท'),
                            column(label: 'สถานะ'),
                            column(label: 'การดำเนินการ'),
                          ],
                          rows: [
                            for (final user in pageUsers)
                              DataRow(
                                key: ValueKey(user.uid),
                                cells: [
                                  DataCell(
                                    Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 170,
                                        ),
                                        child: Text(
                                          user.uid,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 220,
                                        ),
                                        child: Text(
                                          _formatCreatedAt(user.createdAt),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: SizedBox(
                                        width: 200,
                                        child: TextField(
                                          controller:
                                              user.displayNameController,
                                          textAlign: TextAlign.center,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_isSuperAdmin)
                                    DataCell(
                                      Center(
                                        child: SizedBox(
                                          width: 130,
                                          child: DropdownButtonFormField<String>(
                                            key: ValueKey(
                                              '${user.uid}-role-${user.role}',
                                            ),
                                            alignment: Alignment.center,
                                            initialValue:
                                                const {
                                                  'User',
                                                  'Admin',
                                                }.contains(user.role)
                                                ? user.role
                                                : null,
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              border: OutlineInputBorder(),
                                            ),
                                            hint: Text(
                                              user.role,
                                              textAlign: TextAlign.center,
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'User',
                                                child: Center(
                                                  child: Text('User'),
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: 'Admin',
                                                child: Center(
                                                  child: Text('Admin'),
                                                ),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              if (value == null) return;
                                              setState(() => user.role = value);
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  DataCell(
                                    SizedBox(
                                      width: double.infinity,
                                      child: Center(
                                        child: _isSuperAdmin
                                            ? SizedBox(
                                                width: 140,
                                                child: DropdownButtonFormField<String>(
                                                  key: ValueKey(
                                                    '${user.uid}-status-${user.status}',
                                                  ),
                                                  alignment: Alignment.center,
                                                  initialValue:
                                                      const {
                                                        'active',
                                                        'unactive',
                                                      }.contains(user.status)
                                                      ? user.status
                                                      : null,
                                                  decoration:
                                                      const InputDecoration(
                                                        isDense: true,
                                                        border:
                                                            OutlineInputBorder(),
                                                      ),
                                                  hint: Text(
                                                    user.status,
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  items: const [
                                                    DropdownMenuItem(
                                                      value: 'active',
                                                      child: Center(
                                                        child: Text('active'),
                                                      ),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'unactive',
                                                      child: Center(
                                                        child: Text('unactive'),
                                                      ),
                                                    ),
                                                  ],
                                                  onChanged: (value) {
                                                    if (value == null) return;
                                                    setState(
                                                      () => user.status = value,
                                                    );
                                                  },
                                                ),
                                              )
                                            : Text(
                                                user.status,
                                                textAlign: TextAlign.center,
                                              ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: FilledButton.tonalIcon(
                                        onPressed:
                                            _submittingUids.contains(
                                                  user.uid,
                                                ) ||
                                                changesAreEmpty(user) ||
                                                (_isSuperAdmin &&
                                                    _hasPendingAction(user))
                                            ? null
                                            : () => _submitChange(user),
                                        icon: _submittingUids.contains(user.uid)
                                            ? const SizedBox.square(
                                                dimension: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : _hasPendingAction(user)
                                            ? const Icon(Icons.hourglass_top)
                                            : Icon(
                                                _isSuperAdmin
                                                    ? Icons.send
                                                    : Icons.save_outlined,
                                              ),
                                        label: Text(
                                          _isSuperAdmin &&
                                                  _hasPendingAction(user)
                                              ? 'รออนุมัติ'
                                              : _isSuperAdmin
                                              ? 'ส่งยืนยัน'
                                              : 'บันทึก',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text(
                    users.isEmpty
                        ? 'แสดง 0 รายการ'
                        : 'แสดง ${startIndex + 1}-'
                              '${(startIndex + _usersPerPage).clamp(0, users.length)} '
                              'จาก ${users.length} รายการ',
                  ),
                  const Spacer(),
                  if (pageCount > 1) ...[
                    IconButton(
                      tooltip: 'หน้าก่อนหน้า',
                      onPressed: _currentPage == 0
                          ? null
                          : () => setState(() => _currentPage--),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('${_currentPage + 1} / $pageCount'),
                    IconButton(
                      tooltip: 'หน้าถัดไป',
                      onPressed: _currentPage >= pageCount - 1
                          ? null
                          : () => setState(() => _currentPage++),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool changesAreEmpty(_ManagedUser user) => _changesFor(user).isEmpty;

  String _formatCreatedAt(String value) {
    try {
      final dateTime = DateTime.parse(value).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(dateTime);
    } catch (_) {
      return value;
    }
  }
}

class _ManagedUser {
  _ManagedUser({
    required this.uid,
    required this.createdAt,
    required String displayName,
    required this.role,
    required this.status,
  }) : originalDisplayName = displayName,
       originalRole = role,
       originalStatus = status,
       displayNameController = TextEditingController(text: displayName);

  final String uid;
  final String createdAt;
  final String originalDisplayName;
  final String originalRole;
  final String originalStatus;
  final TextEditingController displayNameController;
  String role;
  String status;

  factory _ManagedUser.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('รูปแบบข้อมูลผู้ใช้ไม่ถูกต้อง');
    }
    final json = Map<String, dynamic>.from(value);
    final uid = json['uid'];
    final createdAt = json['created_at'];
    final displayName = json['displayName'];
    final role = json['role'];
    final status = json['status'];
    if (uid is! String ||
        createdAt is! String ||
        displayName is! String ||
        role is! String ||
        status is! String) {
      throw const FormatException('ข้อมูลผู้ใช้ไม่ครบถ้วน');
    }
    return _ManagedUser(
      uid: uid,
      createdAt: createdAt,
      displayName: displayName,
      role: role,
      status: status,
    );
  }
}
