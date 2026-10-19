// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';
import '../database/realtime_invalidation.dart';

class SuperAcceptPage extends StatefulWidget {
  const SuperAcceptPage({super.key});

  @override
  State<SuperAcceptPage> createState() => _SuperAcceptPageState();
}

class _SuperAcceptPageState extends State<SuperAcceptPage> {
  static const _requestsPerPage = 5;

  List<_UserChangeRequest> _requests = [];
  int _pendingPage = 0;
  bool _isLoading = true;
  int _loadVersion = 0;
  String? _error;
  final Set<String> _resolvingRequestIds = {};
  late final RealtimeRefreshBinding _realtimeRefresh;

  @override
  void initState() {
    super.initState();
    _realtimeRefresh = RealtimeRefreshBinding(
      domains: const {RealtimeInvalidationDomain.accounts},
      onRefresh: _loadRequests,
      isMounted: () => mounted,
    );
    _loadRequests();
  }

  @override
  void dispose() {
    _realtimeRefresh.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    final account = TemporaryAccountSession.instance.account;
    if (account == null || account.role != 'SuperAdmin') {
      throw Exception('กรุณาเข้าสู่ระบบด้วยบัญชี SuperAdmin');
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
        functionErrorMessage(error, 'เรียกบริการยืนยันการกระทำไม่สำเร็จ'),
      );
    }
    if (responseData is! Map) {
      throw const FormatException('รูปแบบข้อมูลคำขอยืนยันไม่ถูกต้อง');
    }
    final data = Map<String, dynamic>.from(responseData);
    if (data['error'] is String) throw Exception(data['error'] as String);
    return data;
  }

  String _errorText(Object error) {
    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  Future<void> _loadRequests() async {
    final loadVersion = ++_loadVersion;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _invoke('list-requests');
      final rawRequests = data['requests'];
      if (rawRequests is! List) {
        throw const FormatException('ไม่พบรายการคำขอในข้อมูลตอบกลับ');
      }
      final requests = rawRequests
          .map(_UserChangeRequest.fromJson)
          .toList(growable: false);
      if (!mounted || loadVersion != _loadVersion) return;
      final pendingCount = requests
          .where((request) => request.status == 'pending')
          .length;
      setState(() {
        _requests = requests;
        _pendingPage = _clampPage(_pendingPage, pendingCount);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _isLoading = false;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _resolve(
    _UserChangeRequest changeRequest,
    String decision,
  ) async {
    final isApproval = decision == 'approved';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isApproval ? 'ยืนยันการเปลี่ยนแปลง' : 'ปฏิเสธคำขอ'),
        content: Text(
          isApproval
              ? 'อนุมัติการแก้ไขข้อมูลของ ${changeRequest.targetDisplayName} หรือไม่?'
              : 'ปฏิเสธคำขอแก้ไขข้อมูลของ ${changeRequest.targetDisplayName} หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('กลับ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isApproval ? 'อนุมัติ' : 'ปฏิเสธ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resolvingRequestIds.add(changeRequest.id));
    try {
      await _invoke('resolve-request', {
        'requestId': changeRequest.id,
        'decision': decision,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isApproval ? 'อนุมัติคำขอแล้ว' : 'ปฏิเสธคำขอแล้ว'),
        ),
      );
      await _loadRequests();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorText(error))));
    } finally {
      if (mounted) {
        setState(() => _resolvingRequestIds.remove(changeRequest.id));
      }
    }
  }

  bool _isSameRequester(_UserChangeRequest request) {
    final account = TemporaryAccountSession.instance.account;
    return account != null &&
        account.isSystemAccount == request.requesterIsSystem &&
        account.id == request.requesterId;
  }

  int _clampPage(int page, int itemCount) {
    final pageCount = (itemCount / _requestsPerPage).ceil();
    return pageCount == 0 ? 0 : page.clamp(0, pageCount - 1);
  }

  Widget _buildPagination({
    required int itemCount,
    required int currentPage,
    required ValueChanged<int> onPageChanged,
  }) {
    final pageCount = (itemCount / _requestsPerPage).ceil();
    if (pageCount <= 1) return const SizedBox.shrink();

    final startIndex = currentPage * _requestsPerPage;
    final endIndex = (startIndex + _requestsPerPage).clamp(0, itemCount);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('แสดง ${startIndex + 1}-$endIndex จาก $itemCount รายการ'),
        IconButton(
          tooltip: 'หน้าก่อนหน้า',
          onPressed: currentPage == 0
              ? null
              : () => onPageChanged(currentPage - 1),
          icon: const Icon(Icons.chevron_left),
        ),
        Text('${currentPage + 1} / $pageCount'),
        IconButton(
          tooltip: 'หน้าถัดไป',
          onPressed: currentPage >= pageCount - 1
              ? null
              : () => onPageChanged(currentPage + 1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _requests
        .where((request) => request.status == 'pending')
        .toList(growable: false);
    final pendingPageItems = pending
        .skip(_pendingPage * _requestsPerPage)
        .take(_requestsPerPage);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ยืนยันการกระทำ',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text(_error!, textAlign: TextAlign.center)],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  Text(
                    'รอการยืนยัน (${pending.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (pending.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('ไม่มีคำขอที่รอการยืนยัน'),
                      ),
                    )
                  else
                    ...pendingPageItems.map(
                      (request) => _buildRequestCard(request, isPending: true),
                    ),
                  _buildPagination(
                    itemCount: pending.length,
                    currentPage: _pendingPage,
                    onPageChanged: (page) =>
                        setState(() => _pendingPage = page),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
    _UserChangeRequest request, {
    required bool isPending,
  }) {
    final isResolving = _resolvingRequestIds.contains(request.id);
    final isSameRequester = _isSameRequester(request);
    final changes = <Widget>[
      if (request.requestedDisplayName != null)
        _changeLine(
          'displayName',
          request.currentDisplayName,
          request.requestedDisplayName!,
        ),
      if (request.requestedRole != null)
        _changeLine('role', request.currentRole, request.requestedRole!),
      if (request.requestedStatus != null)
        _changeLine('status', request.currentStatus, request.requestedStatus!),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.targetDisplayName} (${request.targetUid})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('ผู้ส่งคำขอ: ${request.requesterDisplayName}'),
            Text('วันที่ส่ง: ${_formatCreatedAt(request.createdAt)}'),
            Text('สถานะ: ${request.status}'),
            const Divider(height: 20),
            ...changes,
            if (isPending && isSameRequester) ...[
              const SizedBox(height: 8),
              const Text('ผู้ส่งคำขอไม่สามารถยืนยันคำขอของตนเองได้'),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isResolving || isSameRequester
                        ? null
                        : () => _resolve(request, 'rejected'),
                    icon: const Icon(Icons.close),
                    label: const Text('ปฏิเสธ'),
                  ),
                  FilledButton.icon(
                    onPressed: isResolving || isSameRequester
                        ? null
                        : () => _resolve(request, 'approved'),
                    icon: isResolving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('อนุมัติ'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _changeLine(String label, String oldValue, String newValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('$label: $oldValue → $newValue'),
    );
  }

  String _formatCreatedAt(String value) {
    try {
      final dateTime = DateTime.parse(value).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(dateTime);
    } on FormatException {
      return value;
    }
  }
}

class _UserChangeRequest {
  const _UserChangeRequest({
    required this.id,
    required this.createdAt,
    required this.targetUid,
    required this.targetDisplayName,
    required this.currentDisplayName,
    required this.currentRole,
    required this.currentStatus,
    required this.requestedDisplayName,
    required this.requestedRole,
    required this.requestedStatus,
    required this.requesterId,
    required this.requesterIsSystem,
    required this.requesterDisplayName,
    required this.status,
  });

  final String id;
  final String createdAt;
  final String targetUid;
  final String targetDisplayName;
  final String currentDisplayName;
  final String currentRole;
  final String currentStatus;
  final String? requestedDisplayName;
  final String? requestedRole;
  final String? requestedStatus;
  final String requesterId;
  final bool requesterIsSystem;
  final String requesterDisplayName;
  final String status;

  factory _UserChangeRequest.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('รูปแบบคำขอแก้ไขผู้ใช้ไม่ถูกต้อง');
    }
    final json = Map<String, dynamic>.from(value);
    String requiredString(String key) {
      final rawValue = json[key];
      if (rawValue is! String) {
        throw const FormatException('ข้อมูลคำขอแก้ไขผู้ใช้ไม่ครบถ้วน');
      }
      return rawValue;
    }

    String? optionalString(String key) {
      final rawValue = json[key];
      if (rawValue != null && rawValue is! String) {
        throw const FormatException('ข้อมูลคำขอแก้ไขผู้ใช้ไม่ถูกต้อง');
      }
      return rawValue as String?;
    }

    final requesterIsSystem = json['requester_is_system'];
    if (requesterIsSystem is! bool) {
      throw const FormatException('ข้อมูลผู้ส่งคำขอไม่ถูกต้อง');
    }
    return _UserChangeRequest(
      id: requiredString('id'),
      createdAt: requiredString('created_at'),
      targetUid: requiredString('target_uid'),
      targetDisplayName: requiredString('target_display_name'),
      currentDisplayName: requiredString('current_display_name'),
      currentRole: requiredString('old_role'),
      currentStatus: requiredString('current_status'),
      requestedDisplayName: optionalString('requested_display_name'),
      requestedRole: optionalString('requested_role'),
      requestedStatus: optionalString('requested_status'),
      requesterId: requiredString('requester_id'),
      requesterIsSystem: requesterIsSystem,
      requesterDisplayName: requiredString('requester_display_name'),
      status: requiredString('status'),
    );
  }
}
