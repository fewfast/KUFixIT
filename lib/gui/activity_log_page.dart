import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';
import '../database/realtime_invalidation.dart';

class ActivityLogItem {
  final int id;
  final String actorUsername;
  final String actorRole;
  final String? actorDisplayName;
  final String actionType;
  final String actionTitle;
  final String description;
  final String? targetId;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const ActivityLogItem({
    required this.id,
    required this.actorUsername,
    required this.actorRole,
    this.actorDisplayName,
    required this.actionType,
    required this.actionTitle,
    required this.description,
    this.targetId,
    required this.metadata,
    required this.createdAt,
  });

  factory ActivityLogItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(json['created_at'] as String).toLocal();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    Map<String, dynamic> meta = {};
    if (json['metadata'] is Map) {
      meta = Map<String, dynamic>.from(json['metadata'] as Map);
    }

    return ActivityLogItem(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      actorUsername: json['actor_username'] as String? ?? 'system',
      actorRole: json['actor_role'] as String? ?? 'System',
      actorDisplayName: json['actor_display_name'] as String?,
      actionType: json['action_type'] as String? ?? '',
      actionTitle: json['action_title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      targetId: json['target_id'] as String?,
      metadata: meta,
      createdAt: parsedDate,
    );
  }
}

typedef FetchActivityLogsFn = Future<Map<String, dynamic>> Function({
  required int page,
  required int pageSize,
  String? search,
  String? actionType,
  String? actorRole,
  String? startDate,
  String? endDate,
});

class ActivityLogPage extends StatefulWidget {
  final FetchActivityLogsFn? fetchLogs;

  const ActivityLogPage({
    super.key,
    this.fetchLogs,
  });

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final TextEditingController _searchController = TextEditingController();
  late final RealtimeRefreshBinding _realtimeRefresh;
  Timer? _pollingTimer;

  bool _isLoading = true;
  String? _error;
  List<ActivityLogItem> _logs = [];
  int _page = 1;
  final int _pageSize = 5;
  int _totalCount = 0;
  int _totalPages = 1;

  String _selectedActionType = 'ALL';
  String _selectedRole = 'ALL';
  String _selectedDateRangeFilter = 'ALL';
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _realtimeRefresh = RealtimeRefreshBinding(
      domains: const {
        RealtimeInvalidationDomain.accounts,
        RealtimeInvalidationDomain.tickets,
        RealtimeInvalidationDomain.activityLogs,
      },
      onRefresh: () => _loadLogs(silent: true),
      isMounted: () => mounted,
    );
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) {
        _loadLogs(silent: true);
      }
    });
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _realtimeRefresh.dispose();
    _pollingTimer?.cancel();
    _pollingTimer = null;
    super.dispose();
  }

  Future<Map<String, dynamic>> _defaultFetchLogs({
    required int page,
    required int pageSize,
    String? search,
    String? actionType,
    String? actorRole,
    String? startDate,
    String? endDate,
  }) async {
    final account = TemporaryAccountSession.instance.account;
    if (account == null || account.role != 'SuperAdmin') {
      throw Exception('กรุณาเข้าสู่ระบบด้วยบัญชี SuperAdmin');
    }
    if (!SupabaseConnection.isInitialized) {
      throw Exception('ยังไม่ได้เชื่อมต่อ Supabase');
    }

    final payload = <String, dynamic>{
      'action': 'list-activity-logs',
      'page': page,
      'pageSize': pageSize,
      if (search != null && search.isNotEmpty) 'search': search,
      if (actionType != null && actionType != 'ALL') 'actionType': actionType,
      if (actorRole != null && actorRole != 'ALL') 'actorRole': actorRole,
      if (startDate != null && startDate.isNotEmpty) 'startDate': startDate,
      if (endDate != null && endDate.isNotEmpty) 'endDate': endDate,
    };

    late final Object? responseData;
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'superadmin-users',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: payload,
      );
      responseData = response.data;
    } catch (error) {
      throw Exception(
        functionErrorMessage(error, 'โหลดประวัติการกระทำไม่สำเร็จ'),
      );
    }

    if (responseData is! Map) {
      throw const FormatException('รูปแบบข้อมูลประวัติการกระทำไม่ถูกต้อง');
    }
    final data = Map<String, dynamic>.from(responseData);
    if (data['error'] is String) throw Exception(data['error'] as String);
    return data;
  }

  (String?, String?) _resolveDateRange() {
    final now = DateTime.now();
    switch (_selectedDateRangeFilter) {
      case 'TODAY':
        final todayStr = DateFormat('yyyy-MM-dd').format(now);
        return (todayStr, todayStr);
      case '7DAYS':
        final start = now.subtract(const Duration(days: 7));
        return (
          DateFormat('yyyy-MM-dd').format(start),
          DateFormat('yyyy-MM-dd').format(now),
        );
      case '30DAYS':
        final start = now.subtract(const Duration(days: 30));
        return (
          DateFormat('yyyy-MM-dd').format(start),
          DateFormat('yyyy-MM-dd').format(now),
        );
      case 'CUSTOM':
        if (_customDateRange != null) {
          return (
            DateFormat('yyyy-MM-dd').format(_customDateRange!.start),
            DateFormat('yyyy-MM-dd').format(_customDateRange!.end),
          );
        }
        return (null, null);
      default:
        return (null, null);
    }
  }

  Future<void> _loadLogs({int? targetPage, bool silent = false}) async {
    final pageToLoad = targetPage ?? _page;
    if (!silent || _logs.isEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final (startDate, endDate) = _resolveDateRange();

    try {
      final fetchFn = widget.fetchLogs ?? _defaultFetchLogs;
      final data = await fetchFn(
        page: pageToLoad,
        pageSize: _pageSize,
        search: _searchController.text.trim(),
        actionType: _selectedActionType,
        actorRole: _selectedRole,
        startDate: startDate,
        endDate: endDate,
      );

      final rawList = data['logs'];
      if (rawList is! List) {
        throw const FormatException('ไม่พบรายการประวัติในข้อมูลตอบกลับ');
      }

      final items = rawList
          .whereType<Map>()
          .map((item) => ActivityLogItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      final total = data['totalCount'] is num
          ? (data['totalCount'] as num).toInt()
          : items.length;
      final totalPages = data['totalPages'] is num
          ? (data['totalPages'] as num).toInt()
          : (total == 0 ? 1 : ((total - 1) ~/ _pageSize + 1));

      if (!mounted) return;
      setState(() {
        _logs = items;
        _page = pageToLoad;
        _totalCount = total;
        _totalPages = totalPages < 1 ? 1 : totalPages;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        if (!silent || _logs.isEmpty) {
          _error = msg;
        }
        _isLoading = false;
      });
    }
  }

  Color _getRoleColor(String role) {
    return switch (role.toLowerCase()) {
      'superadmin' => Colors.deepPurple,
      'admin' => Colors.blue.shade700,
      'technician' => Colors.orange.shade800,
      'user' => Colors.green.shade700,
      _ => Colors.grey.shade700,
    };
  }

  IconData _getRoleIcon(String role) {
    return switch (role.toLowerCase()) {
      'superadmin' => Icons.shield_outlined,
      'admin' => Icons.manage_accounts_outlined,
      'technician' => Icons.handyman_outlined,
      'user' => Icons.person_outline,
      _ => Icons.info_outline,
    };
  }

  IconData? _getActionIcon(String actionType) {
    return switch (actionType) {
      'CHANGE_USER_DISPLAY_NAME' => Icons.badge_outlined,
      'CHANGE_DISPLAY_NAME' => Icons.drive_file_rename_outline,
      'EDIT_TICKET' => Icons.edit_note_outlined,
      'CREATE_TECH_TEAM' => Icons.group_add_outlined,
      'SCHEDULE_TECH_TEAM' => Icons.schedule_outlined,
      'DELETE_TECH_TEAM' => Icons.group_remove_outlined,
      'REPORT_APPROVE' => Icons.check_circle_outline,
      'REPORT_REJECT' => Icons.cancel_outlined,
      'TECH_SUBMIT' => Icons.send_outlined,
      'TICKET_ASSIGN' => Icons.assignment_ind_outlined,
      'ROLE_CHANGE' || 'ROLE_CHANGE_APPROVE' || 'ROLE_CHANGE_REJECT' || 'USER_STATUS' =>
        Icons.admin_panel_settings_outlined,
      _ => null,
    };
  }

  void _showMetadataDialog(ActivityLogItem log) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'รายละเอียด: ${log.actionTitle}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailRow('ผู้กระทำ', '${log.actorDisplayName ?? log.actorUsername} (${log.actorRole})'),
                  _detailRow('เวลาที่บันทึก', DateFormat('dd/MM/yyyy HH:mm:ss น.').format(log.createdAt)),
                  if (log.targetId != null) _detailRow('รหัสเป้าหมาย (Target ID)', log.targetId!),
                  _detailRow('รายละเอียด', log.description),
                  const Divider(height: 24),
                  const Text(
                    'ข้อมูลเพิ่มเติม (Metadata):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SelectableText(
                      log.metadata.isEmpty
                          ? '(ไม่มีข้อมูลเพิ่มเติม)'
                          : const JsonEncoder.withIndent('  ').convert(log.metadata),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ปิด'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _loadLogs(targetPage: 1),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildFiltersCard(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildErrorCard()
            else if (_logs.isEmpty)
              _buildEmptyCard()
            else ...[
              _buildLogList(),
              const SizedBox(height: 16),
              _buildPagination(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 28, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'ประวัติการกระทำทั้งหมด (Activity Logs)',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: _isLoading ? 'กำลังโหลด...' : 'รีเฟรชข้อมูล',
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: _isLoading ? null : () => _loadLogs(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'บันทึกและตรวจสอบประวัติการทำรายการทั้งหมดในระบบ (เฉพาะ SuperAdmin)',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildFiltersCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ค้นหาชื่อผู้กระทำ, รายละเอียด, หรือ Target ID / Ticket ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadLogs(targetPage: 1);
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: (_) => _loadLogs(targetPage: 1),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedActionType,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('ประเภท: ทั้งหมด')),
                        DropdownMenuItem(
                          value: 'EDIT_TICKET',
                          child: Text('แก้ไขคำร้องแจ้งซ่อม'),
                        ),
                        DropdownMenuItem(
                          value: 'CREATE_TECH_TEAM,SCHEDULE_TECH_TEAM,DELETE_TECH_TEAM',
                          child: Text('จัดการทีมช่าง'),
                        ),
                        DropdownMenuItem(
                          value: 'CHANGE_DISPLAY_NAME,CHANGE_USER_DISPLAY_NAME',
                          child: Text('เปลี่ยนชื่อที่แสดง (ตนเอง/ผู้อื่น)'),
                        ),
                        DropdownMenuItem(
                          value: 'REPORT_APPROVE,REPORT_REJECT',
                          child: Text('ตรวจงานช่าง (อนุมัติ/ปฏิเสธ)'),
                        ),
                        DropdownMenuItem(value: 'TICKET_ASSIGN', child: Text('มอบหมายงานซ่อม')),
                        DropdownMenuItem(
                          value: 'ROLE_CHANGE,ROLE_CHANGE_APPROVE,ROLE_CHANGE_REJECT,USER_STATUS',
                          child: Text('จัดการสิทธิ์และผู้ใช้'),
                        ),
                        DropdownMenuItem(value: 'TECH_SUBMIT', child: Text('ส่งงานช่าง')),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => _selectedActionType = val);
                        _loadLogs(targetPage: 1);
                      },
                    ),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedRole,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('บทบาท: ทั้งหมด')),
                        DropdownMenuItem(value: 'SuperAdmin', child: Text('SuperAdmin')),
                        DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                        DropdownMenuItem(value: 'Technician', child: Text('Technician')),
                        DropdownMenuItem(value: 'User', child: Text('User')),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() => _selectedRole = val);
                        _loadLogs(targetPage: 1);
                      },
                    ),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedDateRangeFilter,
                      isDense: true,
                      items: [
                        const DropdownMenuItem(value: 'ALL', child: Text('ช่วงเวลา: ทั้งหมด')),
                        const DropdownMenuItem(value: 'TODAY', child: Text('วันนี้')),
                        const DropdownMenuItem(value: '7DAYS', child: Text('7 วันล่าสุด')),
                        const DropdownMenuItem(value: '30DAYS', child: Text('30 วันล่าสุด')),
                        DropdownMenuItem(
                          value: 'CUSTOM',
                          child: Text(
                            _customDateRange == null
                                ? 'กำหนดช่วงวันเอง...'
                                : '${DateFormat('dd/MM/yy').format(_customDateRange!.start)} - ${DateFormat('dd/MM/yy').format(_customDateRange!.end)}',
                          ),
                        ),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        if (val == 'CUSTOM') {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2025),
                            lastDate: DateTime.now().add(const Duration(days: 1)),
                            initialDateRange: _customDateRange ??
                                DateTimeRange(
                                  start: DateTime.now().subtract(const Duration(days: 7)),
                                  end: DateTime.now(),
                                ),
                          );
                          if (picked != null) {
                            setState(() {
                              _selectedDateRangeFilter = 'CUSTOM';
                              _customDateRange = picked;
                            });
                            _loadLogs(targetPage: 1);
                          }
                        } else {
                          setState(() {
                            _selectedDateRangeFilter = val;
                            _customDateRange = null;
                          });
                          _loadLogs(targetPage: 1);
                        }
                      },
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _loadLogs(targetPage: 1),
                  icon: const Icon(Icons.filter_alt, size: 18),
                  label: const Text('ค้นหา'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList() {
    return Column(
      children: [
        for (final log in _logs) _buildLogCard(log),
      ],
    );
  }

  String _formatActorHeader(ActivityLogItem log) {
    final role = log.actorRole.trim();
    final username = log.actorUsername.trim();
    final displayName = log.actorDisplayName?.trim();
    
    // ดึง uid จริงจาก metadata ถ้าไม่มีให้ใช้ username
    final uid = (log.metadata['uid'] as String?) ??
                (log.metadata['actor_uid'] as String?) ??
                username;

    if (role.toLowerCase() == 'system') {
      return displayName ?? 'ระบบอัตโนมัติ';
    } else if (role == 'SuperAdmin') {
      // SuperAdmin: แสดง SuperAdmin1 หรือ SuperAdmin2 โดยไม่มีวงเล็บข้างหลัง
      final lowerUser = username.toLowerCase();
      final lowerDisplay = (displayName ?? '').toLowerCase();
      if (lowerUser.contains('2') || lowerDisplay.contains('2')) {
        return 'SuperAdmin2';
      }
      return 'SuperAdmin1';
    } else if (role == 'Technician') {
      // Technician: แสดงเป็น "ทีมช่าง [teamName] (uid)"
      final team = (log.metadata['team'] as String?) ??
                   (log.metadata['team_name'] as String?) ??
                   'techteam';
      return 'ทีมช่าง $team ($uid)';
    } else if (role == 'Admin') {
      // Admin: แสดง "[DisplayName จริง] (uid จริง)"
      final name = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : username;
      return '$name ($uid)';
    } else if (role == 'User') {
      // User: แสดง "[DisplayName] (uid)"
      final name = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : username;
      return '$name ($uid)';
    }

    // บทบาทอื่นๆ
    final name = (displayName != null && displayName.isNotEmpty) ? displayName : username;
    return '$name ($uid)';
  }

  Widget _buildLogCard(ActivityLogItem log) {
    final roleColor = _getRoleColor(log.actorRole);
    final formattedTime = DateFormat('dd/MM/yyyy HH:mm น.').format(log.createdAt);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showMetadataDialog(log),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: roleColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getRoleIcon(log.actorRole), size: 13, color: roleColor),
                        const SizedBox(width: 4),
                        Text(
                          log.actorRole,
                          style: TextStyle(
                            color: roleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatActorHeader(log),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        formattedTime,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_getActionIcon(log.actionType) != null) ...[
                              Icon(
                                _getActionIcon(log.actionType),
                                size: 18,
                                color: roleColor,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                log.actionTitle,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          log.description,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
                        ),
                        if (log.actionType == 'CHANGE_USER_DISPLAY_NAME' &&
                            (log.metadata['old_display_name'] != null ||
                                log.metadata['new_display_name'] != null)) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'ชื่อเดิม: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${log.metadata['old_display_name'] ?? '-'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade700,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: Colors.grey,
                              ),
                              Text(
                                'ชื่อใหม่: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${log.metadata['new_display_name'] ?? '-'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (log.targetId != null) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('#${log.targetId}'),
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: Colors.blueGrey.shade50,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final startItem = _totalCount == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final endItem = (_page * _pageSize) > _totalCount ? _totalCount : (_page * _pageSize);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'แสดง $startItem - $endItem จากทั้งหมด $_totalCount รายการ',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'หน้าก่อนหน้า',
              onPressed: _page > 1 ? () => _loadLogs(targetPage: _page - 1) : null,
            ),
            Text(
              'หน้าที่ $_page / $_totalPages',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'หน้าถัดไป',
              onPressed: _page < _totalPages ? () => _loadLogs(targetPage: _page + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyCard() {
    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.history_outlined, size: 54, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'ไม่พบประวัติการกระทำตามเงื่อนไขที่เลือก',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'ลองเปลี่ยนเงื่อนไขค้นหาหรือตัวกรองเพื่อดูข้อมูลเพิ่มเติม',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 44, color: Colors.red.shade700),
            const SizedBox(height: 10),
            Text(
              _error ?? 'เกิดข้อผิดพลาดในการโหลดข้อมูล',
              style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _loadLogs(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('ลองใหม่อีกครั้ง'),
            ),
          ],
        ),
      ),
    );
  }
}
