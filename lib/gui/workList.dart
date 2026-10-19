// ignore_for_file: file_names

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlong;

import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';
import '../database/realtime_invalidation.dart';
import 'technician_report_rules.dart';

const _maxReportPhotoBytes = 2 * 1024 * 1024;

class WorkList extends StatefulWidget {
  const WorkList({
    super.key,
    this.fetchTickets,
    this.submitReport,
    this.imagePicker,
    this.invalidations,
  });

  final Future<List<WorkTicket>> Function()? fetchTickets;
  final SubmitWorkReport? submitReport;
  final ImagePicker? imagePicker;
  final Stream<RealtimeInvalidationDomain>? invalidations;

  @override
  State<WorkList> createState() => _WorkListState();
}

class _WorkListState extends State<WorkList> {
  List<WorkTicket> _tickets = const [];
  bool _initialLoading = true;
  bool _refreshing = false;
  int _loadVersion = 0;
  String? _error;
  final Set<String> _submitting = {};
  final Map<String, WorkTicketDraft> _drafts = {};
  late final RealtimeRefreshBinding _realtimeRefresh;

  WorkTicketDraft _draftFor(String ticketId) {
    return _drafts.putIfAbsent(ticketId, WorkTicketDraft.new);
  }

  @override
  void initState() {
    super.initState();
    _realtimeRefresh = RealtimeRefreshBinding(
      domains: const {
        RealtimeInvalidationDomain.tickets,
        RealtimeInvalidationDomain.technicians,
        RealtimeInvalidationDomain.reports,
        RealtimeInvalidationDomain.storage,
      },
      onRefresh: () => _loadTickets(isBackground: true),
      isMounted: () => mounted,
      invalidations: widget.invalidations,
    );
    _loadTickets();
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
    if (account == null ||
        account.role != 'Technician' ||
        account.accessToken.isEmpty) {
      throw Exception('กรุณาเข้าสู่ระบบด้วยบัญชีช่าง');
    }
    if (!SupabaseConnection.isInitialized) {
      throw Exception('ยังไม่ได้เชื่อมต่อ Supabase');
    }
    late final Object? responseData;
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'technician-work',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {'action': action, ...body},
      );
      responseData = response.data;
    } catch (error) {
      throw Exception(
        functionErrorMessage(error, 'เรียกบริการรายงานงานช่างไม่สำเร็จ'),
      );
    }
    if (responseData is! Map) {
      throw const FormatException('รูปแบบข้อมูลจากระบบงานช่างไม่ถูกต้อง');
    }
    final data = Map<String, dynamic>.from(responseData);
    if (data['error'] is String) throw Exception(data['error'] as String);
    return data;
  }

  Future<void> _loadTickets({bool isBackground = false}) async {
    final loadVersion = ++_loadVersion;
    final isInitial = _initialLoading && _tickets.isEmpty && !isBackground;
    setState(() {
      if (isInitial) {
        _initialLoading = true;
        _error = null;
      } else {
        _refreshing = true;
      }
    });
    try {
      final List<WorkTicket> tickets;
      if (widget.fetchTickets != null) {
        tickets = await widget.fetchTickets!();
      } else {
        final data = await _invoke('list-technician-tickets');
        final raw = data['tickets'];
        if (raw is! List) {
          throw const FormatException('ไม่พบรายการ ticket ที่ได้รับมอบหมาย');
        }
        tickets = raw.map(WorkTicket.fromJson).toList(growable: false);
      }
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _tickets = tickets;
        _initialLoading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _initialLoading = false;
        _refreshing = false;
        if (_tickets.isEmpty) {
          _error = _errorText(error);
        } else {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('อัปเดตข้อมูลไม่สำเร็จ: ${_errorText(error)}'),
            ),
          );
        }
      });
    }
  }

  Future<void> _submitReport(
    WorkTicket ticket, {
    required String comment,
    required List<DeviceReportDraft> deviceResults,
  }) async {
    setState(() => _submitting.add(ticket.ticketId));
    try {
      if (widget.submitReport != null) {
        await widget.submitReport!(
          WorkReportDraft(comment: comment, deviceResults: deviceResults),
        );
      } else {
        final request = <String, Object?>{
          'ticketId': ticket.ticketId,
          'comment': comment.trim(),
          'deviceResults': [
            for (final result in deviceResults)
              {
                'deviceid': result.deviceId,
                'row_index': result.rowIndex,
                'success': result.success,
                if (result.photo != null) ...{
                  'photoBase64': base64Encode(result.photo!.bytes),
                  'photoName': result.photo!.name,
                  'photoContentType': result.photo!.contentType,
                },
              },
          ],
        };
        await _invoke('submit-report', request);
      }
      _drafts.remove(ticket.ticketId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งรายงานให้ Admin ตรวจแล้ว')),
      );
      await _loadTickets(isBackground: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งรายงานไม่สำเร็จ: ${_errorText(error)}')),
      );
    } finally {
      if (mounted) setState(() => _submitting.remove(ticket.ticketId));
    }
  }

  String _errorText(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final showInitialLoading = _initialLoading && _tickets.isEmpty;
    final showError = _error != null && _tickets.isEmpty;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'งานที่ได้รับ',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text('รายการงานซ่อมที่ได้รับมอบหมาย'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_refreshing)
            const SizedBox(
              height: 4,
              child: LinearProgressIndicator(minHeight: 2),
            )
          else
            const SizedBox(height: 4),
          const SizedBox(height: 8),
          if (showInitialLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (showError)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _loadTickets(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              ),
            )
          else if (_tickets.isEmpty)
            const Expanded(
              child: Center(child: Text('ยังไม่มีงานที่ได้รับมอบหมาย')),
            )
          else
            Expanded(
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _tickets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final ticket = _tickets[index];
                  return _WorkTicketCard(
                    key: ValueKey('work-ticket-${ticket.ticketId}'),
                    ticket: ticket,
                    draft: _draftFor(ticket.ticketId),
                    picker: widget.imagePicker,
                    submitting: _submitting.contains(ticket.ticketId),
                    onSubmit: (draft) => _submitReport(
                      ticket,
                      comment: draft.comment,
                      deviceResults: draft.deviceResults,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

typedef SubmitWorkReport = Future<void> Function(WorkReportDraft draft);

class WorkReportDraft {
  const WorkReportDraft({required this.comment, required this.deviceResults});

  final String comment;
  final List<DeviceReportDraft> deviceResults;
}

class PickedReportPhoto {
  const PickedReportPhoto({
    required this.bytes,
    required this.name,
    required this.contentType,
  });

  final Uint8List bytes;
  final String name;
  final String contentType;
}

class DeviceReportDraft {
  const DeviceReportDraft({
    required this.deviceId,
    required this.rowIndex,
    required this.success,
    required this.photo,
  });

  final int deviceId;
  final int rowIndex;
  final bool success;
  final PickedReportPhoto? photo;
}

class WorkTicketDraft {
  WorkTicketDraft({
    this.comment = '',
    Map<int, bool?>? deviceOutcomes,
    Map<int, PickedReportPhoto>? devicePhotos,
    this.pendingPhotoDeviceId,
  })  : deviceOutcomes = deviceOutcomes ?? <int, bool?>{},
        devicePhotos = devicePhotos ?? <int, PickedReportPhoto>{};

  String comment;
  final Map<int, bool?> deviceOutcomes;
  final Map<int, PickedReportPhoto> devicePhotos;
  int? pendingPhotoDeviceId;
}

class _WorkTicketCard extends StatefulWidget {
  const _WorkTicketCard({
    required this.ticket,
    required this.draft,
    required this.submitting,
    required this.onSubmit,
    this.picker,
    super.key,
  });

  final WorkTicket ticket;
  final WorkTicketDraft draft;
  final bool submitting;
  final SubmitWorkReport onSubmit;
  final ImagePicker? picker;

  @override
  State<_WorkTicketCard> createState() => _WorkTicketCardState();
}

class _WorkTicketCardState extends State<_WorkTicketCard> {
  late final TextEditingController _commentController;
  late final ImagePicker _picker;

  Map<int, bool?> get _deviceOutcomes => widget.draft.deviceOutcomes;
  Map<int, PickedReportPhoto> get _devicePhotos => widget.draft.devicePhotos;

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? ImagePicker();
    _commentController = TextEditingController(text: widget.draft.comment);
    _commentController.addListener(_onCommentChanged);
    _checkLostData();
  }

  void _onCommentChanged() {
    widget.draft.comment = _commentController.text;
  }

  @override
  void didUpdateWidget(covariant _WorkTicketCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      if (_commentController.text != widget.draft.comment) {
        _commentController.text = widget.draft.comment;
      }
    }
  }

  @override
  void dispose() {
    _commentController.removeListener(_onCommentChanged);
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _checkLostData() async {
    try {
      final response = await _picker.retrieveLostData();
      if (response.isEmpty || !mounted) return;
      final file = response.file ??
          (response.files != null && response.files!.isNotEmpty
              ? response.files!.first
              : null);
      if (file == null) return;
      final targetDeviceId = widget.draft.pendingPhotoDeviceId ??
          (widget.ticket.devices.length == 1
              ? widget.ticket.devices.first.deviceId
              : null);
      if (targetDeviceId != null) {
        await _applyPickedImage(targetDeviceId, file);
      }
    } catch (error) {
      debugPrint('ImagePicker retrieveLostData error: $error');
    }
  }

  Future<void> _pickPhoto(int deviceId) async {
    try {
      widget.draft.pendingPhotoDeviceId = deviceId;
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      await _applyPickedImage(deviceId, image);
    } on FormatException catch (error) {
      _message(error.message);
    } on Exception catch (error) {
      _message('เลือกรูปไม่สำเร็จ: $error');
    } finally {
      widget.draft.pendingPhotoDeviceId = null;
    }
  }

  Future<void> _applyPickedImage(int deviceId, XFile image) async {
    final fileName = _effectiveFileName(image);
    final contentType = _contentType(fileName);
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxReportPhotoBytes) {
      _message('รูปต้องมีขนาดไม่เกิน 2 MB');
      return;
    }
    setState(
      () => _devicePhotos[deviceId] = PickedReportPhoto(
        bytes: bytes,
        name: fileName,
        contentType: contentType,
      ),
    );
  }

  String _effectiveFileName(XFile file) {
    if (file.name.isNotEmpty && file.name.contains('.')) return file.name;
    if (file.path.isNotEmpty && file.path.contains('.')) {
      return file.path.split(RegExp(r'[/\\]')).last;
    }
    return file.name.isNotEmpty ? file.name : file.path;
  }

  String _contentType(String name) {
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw const FormatException('รองรับเฉพาะรูป JPG, PNG หรือ WEBP'),
    };
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    final devices = widget.ticket.devices;
    final outcomes = [
      for (final device in devices) _deviceOutcomes[device.deviceId],
    ];
    final validationError = validateTechnicianReport(
      outcomes: outcomes,
      hasPhoto: [
        for (final device in devices) _devicePhotos[device.deviceId] != null,
      ],
      comment: _commentController.text,
    );
    if (validationError != null) {
      _message(validationError);
      return;
    }
    final outcomesResolved = outcomes.cast<bool>();
    await widget.onSubmit(
      WorkReportDraft(
        comment: effectiveTechnicianReportComment(
          outcomes: outcomesResolved,
          comment: _commentController.text,
        ),
        deviceResults: [
          for (final device in devices)
            DeviceReportDraft(
              deviceId: device.deviceId,
              rowIndex: device.rowIndex,
              success: _deviceOutcomes[device.deviceId]!,
              photo: _devicePhotos[device.deviceId],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    final report = ticket.report;
    final status = report?.status;
    final isPending = status == 'under_review';
    final successAccepted =
        status == 'approved' && report?.outcome == 'success';
    final ticketFinished = ticket.status == 'finish';
    final acceptedFailure =
        status == 'approved' && report?.outcome == 'failure';
    final building = ticket.building == 'other'
        ? 'อื่นๆ'
        : 'อาคาร ${ticket.building}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ticket ${ticket.ticketId}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (isPending)
                  const _ReportStatusChip(
                    label: 'อยู่ในระหว่างตรวจ',
                    icon: Icons.hourglass_top,
                  )
                else if (successAccepted && ticketFinished)
                  const _ReportStatusChip(
                    label: 'สำเร็จ · ตรวจงานผ่าน',
                    icon: Icons.verified,
                  )
                else if (successAccepted)
                  const _ReportStatusChip(
                    label: 'ตรวจงานผ่าน · ยังมีอุปกรณ์ค้าง',
                    icon: Icons.verified_outlined,
                  )
                else if (acceptedFailure)
                  const _ReportStatusChip(
                    label: 'ตรวจงานผ่าน · ทำงานต่อ',
                    icon: Icons.verified_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _InfoItem(label: 'อาคาร', value: building),
                _InfoItem(label: 'บริเวณ', value: ticket.area ?? '-'),
                _InfoItem(label: 'ชั้น', value: ticket.floor ?? '-'),
                _InfoItem(label: 'ห้อง', value: ticket.room ?? '-'),
                OutlinedButton.icon(
                  onPressed: () => _showMap(context, ticket),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('ดูแผนที่'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('อุปกรณ์ย่อย', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (ticket.devices.isEmpty)
              const Text('ไม่มีข้อมูลอุปกรณ์ย่อย')
            else
              ...ticket.devices.map(
                (device) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${device.deviceId}. '),
                      Expanded(
                        child: Text(
                          [
                            device.name,
                            if (device.description?.trim().isNotEmpty == true)
                              device.description!.trim(),
                          ].whereType<String>().join(' · '),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (report != null && !isPending) ...[
              const SizedBox(height: 12),
              _PreviousReport(ticket: ticket, report: report),
            ],
            if (isPending)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('ส่งรายงานแล้ว กรุณารอ Admin ตรวจงาน'),
              )
            else if (!successAccepted || !ticketFinished) ...[
              const Divider(height: 24),
              Text(
                'ส่งรายงานผลการทำงาน',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              ...ticket.devices.map(_buildDeviceReportInput),
              const SizedBox(height: 10),
              TextField(
                controller: _commentController,
                enabled: !widget.submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 5000,
                decoration: InputDecoration(
                  labelText:
                      _deviceOutcomes.values.any((value) => value == false)
                      ? 'ความคิดเห็นสำหรับงานที่ไม่สำเร็จ *'
                      : 'ความคิดเห็น (ไม่บังคับ)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: widget.submitting ? null : _submit,
                  icon: widget.submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('ส่งงาน'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceReportInput(WorkDevice device) {
    final outcome = _deviceOutcomes[device.deviceId];
    final photo = _devicePhotos[device.deviceId];
    final title = [
      device.name?.trim(),
      device.description?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'อุปกรณ์ ${device.deviceId}${title.isEmpty ? '' : ' · $title'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<bool>(
              initialValue: outcome,
              decoration: const InputDecoration(
                labelText: 'ผลการซ่อม',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: true, child: Text('ซ่อมสำเร็จ')),
                DropdownMenuItem(
                  value: false,
                  child: Text('ไม่สำเร็จ / ทำไม่ทัน'),
                ),
              ],
              onChanged: widget.submitting
                  ? null
                  : (value) => setState(() {
                      _deviceOutcomes[device.deviceId] = value;
                      if (value != true) _devicePhotos.remove(device.deviceId);
                    }),
            ),
            if (outcome == true) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.submitting
                    ? null
                    : () => _pickPhoto(device.deviceId),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  photo == null ? 'แนบรูปผลลัพธ์ *' : 'เปลี่ยนรูปผลลัพธ์',
                ),
              ),
              if (photo != null) ...[
                Text(photo.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    photo.bytes,
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviousReport extends StatelessWidget {
  const _PreviousReport({required this.ticket, required this.report});

  final WorkTicket ticket;
  final WorkReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.outcome == 'success'
                ? 'รายงานล่าสุด: สำเร็จ'
                : 'รายงานล่าสุด: ไม่สำเร็จ',
          ),
          if (report.comment?.trim().isNotEmpty == true)
            Text('ความคิดเห็น: ${report.comment}'),
          if (report.deviceResults.where((result) => result.success).isEmpty &&
              report.photoUrl == null)
            const Text('ไม่มีอุปกรณ์ที่ซ่อมสำเร็จ')
          else if (report.deviceResults
              .where((result) => result.success)
              .isEmpty)
            TextButton.icon(
              onPressed: () =>
                  _showImage(context, ticket.ticketId, report.photoUrl!),
              icon: const Icon(Icons.image_outlined),
              label: const Text('ดูรูปผลลัพธ์'),
            )
          else ...[
            Text(
              'อุปกรณ์ที่ซ่อมสำเร็จ: ${report.deviceResults.where((result) => result.success).map((result) => result.deviceId).join(', ')}',
            ),
            for (final result in report.deviceResults.where(
              (result) => result.success,
            ))
              if (result.photoUrl != null)
                TextButton.icon(
                  onPressed: () =>
                      _showImage(context, ticket.ticketId, result.photoUrl!),
                  icon: const Icon(Icons.image_outlined),
                  label: Text('ดูรูปอุปกรณ์ ${result.deviceId}'),
                ),
          ],
        ],
      ),
    );
  }
}

class TechnicianWorkReviewPage extends StatefulWidget {
  const TechnicianWorkReviewPage({super.key});

  @override
  State<TechnicianWorkReviewPage> createState() =>
      _TechnicianWorkReviewPageState();
}

class _TechnicianWorkReviewPageState extends State<TechnicianWorkReviewPage> {
  List<_ReviewReport> _reports = const [];
  bool _loading = true;
  int _loadVersion = 0;
  String? _error;
  final Set<String> _reviewing = {};
  late final RealtimeRefreshBinding _realtimeRefresh;

  @override
  void initState() {
    super.initState();
    _realtimeRefresh = RealtimeRefreshBinding(
      domains: const {
        RealtimeInvalidationDomain.tickets,
        RealtimeInvalidationDomain.reports,
        RealtimeInvalidationDomain.storage,
      },
      onRefresh: _loadReports,
      isMounted: () => mounted,
    );
    _loadReports();
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
    if (account == null ||
        !{'Admin', 'SuperAdmin'}.contains(account.role) ||
        account.accessToken.isEmpty) {
      throw Exception('กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลระบบ');
    }
    if (!SupabaseConnection.isInitialized) {
      throw Exception('ยังไม่ได้เชื่อมต่อ Supabase');
    }
    late final Object? responseData;
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'technician-work',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {'action': action, ...body},
      );
      responseData = response.data;
    } catch (error) {
      throw Exception(
        functionErrorMessage(error, 'เรียกบริการตรวจงานช่างไม่สำเร็จ'),
      );
    }
    if (responseData is! Map) {
      throw const FormatException('รูปแบบข้อมูลรายงานไม่ถูกต้อง');
    }
    final data = Map<String, dynamic>.from(responseData);
    if (data['error'] is String) throw Exception(data['error'] as String);
    return data;
  }

  Future<void> _loadReports() async {
    final loadVersion = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _invoke('admin-list-reports');
      final raw = data['reports'];
      if (raw is! List) {
        throw const FormatException('ไม่พบรายการรายงานที่รอตรวจ');
      }
      final reports = raw.map(_ReviewReport.fromJson).toList(growable: false);
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _error = _errorText(error);
        _loading = false;
      });
    }
  }

  Future<void> _review(_ReviewReport report, String decision) async {
    final approve = decision == 'approve';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'ยืนยันการตรวจงาน' : 'ปฏิเสธรายงาน'),
        content: Text(
          approve
              ? 'ยืนยันรายงานของ Ticket ${report.ticketId} หรือไม่?'
              : 'ปฏิเสธรายงานของ Ticket ${report.ticketId} และส่งกลับให้ช่างทำใหม่หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'ยืนยัน' : 'ปฏิเสธ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _reviewing.add(report.id));
    try {
      await _invoke('admin-review-report', {
        'reportId': report.id,
        'decision': decision,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'ตรวจงานและยืนยันแล้ว' : 'ส่งกลับให้ช่างทำใหม่แล้ว',
          ),
        ),
      );
      await _loadReports();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกผลตรวจไม่สำเร็จ: ${_errorText(error)}')),
      );
    } finally {
      if (mounted) setState(() => _reviewing.remove(report.id));
    }
  }

  String _errorText(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ตรวจงานช่าง',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text('ตรวจสอบรายงานและยืนยันหรือส่งกลับให้ช่างแก้ไข'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error case final error?)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text(error, textAlign: TextAlign.center)],
                ),
              ),
            )
          else if (_reports.isEmpty)
            const Expanded(child: Center(child: Text('ไม่มีรายงานรอตรวจ')))
          else
            Expanded(
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final report = _reports[index];
                  return _ReviewReportCard(
                    report: report,
                    busy: _reviewing.contains(report.id),
                    onApprove: () => _review(report, 'approve'),
                    onReject: () => _review(report, 'reject'),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewReportCard extends StatelessWidget {
  const _ReviewReportCard({
    required this.report,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final _ReviewReport report;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final outcomeText = report.outcome == 'success' ? 'สำเร็จ' : 'ไม่สำเร็จ';
    final building = report.building == 'other'
        ? 'อื่นๆ'
        : 'อาคาร ${report.building}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ticket ${report.ticketId}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const _ReportStatusChip(
                  label: 'อยู่ในระหว่างตรวจ',
                  icon: Icons.hourglass_top,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _InfoItem(label: 'ช่าง', value: report.technicianName),
                _InfoItem(label: 'สถานะงาน', value: outcomeText),
                _InfoItem(label: 'อาคาร', value: building),
                _InfoItem(label: 'บริเวณ', value: report.area ?? '-'),
                _InfoItem(label: 'ชั้น', value: report.floor ?? '-'),
                _InfoItem(label: 'ห้อง', value: report.room ?? '-'),
                _InfoItem(
                  label: 'ส่งเมื่อ',
                  value: _formatDate(report.submittedAt),
                ),
              ],
            ),
            if (report.comment?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text('ความคิดเห็น: ${report.comment}'),
            ],
            if (report.deviceResults
                    .where((result) => result.success)
                    .isEmpty &&
                report.photoUrl == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('ไม่มีอุปกรณ์ที่ซ่อมสำเร็จ'),
              )
            else if (report.deviceResults
                .where((result) => result.success)
                .isEmpty)
              TextButton.icon(
                onPressed: () =>
                    _showImage(context, report.ticketId, report.photoUrl!),
                icon: const Icon(Icons.image_outlined),
                label: const Text('ดูรูปผลลัพธ์'),
              )
            else ...[
              Text(
                'อุปกรณ์ที่ซ่อมสำเร็จ: ${report.deviceResults.where((result) => result.success).map((result) => result.deviceId).join(', ')}',
              ),
              for (final result in report.deviceResults.where(
                (result) => result.success,
              ))
                if (result.photoUrl != null)
                  TextButton.icon(
                    onPressed: () =>
                        _showImage(context, report.ticketId, result.photoUrl!),
                    icon: const Icon(Icons.image_outlined),
                    label: Text('ดูรูปอุปกรณ์ ${result.deviceId}'),
                  ),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onReject,
                  icon: const Icon(Icons.close),
                  label: const Text('ปฏิเสธ'),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('ยืนยัน'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WorkTicket {
  const WorkTicket({
    required this.ticketId,
    required this.building,
    required this.area,
    required this.floor,
    required this.room,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.devices,
    required this.report,
  });

  final String ticketId;
  final String building;
  final String? area;
  final String? floor;
  final String? room;
  final double latitude;
  final double longitude;
  final String status;
  final List<WorkDevice> devices;
  final WorkReport? report;

  factory WorkTicket.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('ข้อมูล ticket ไม่ถูกต้อง');
    final json = Map<String, dynamic>.from(value);
    final id = json['TicketId'];
    final building = json['building'];
    final latitude = json['latitude'];
    final longitude = json['longtitude'];
    final status = json['status'];
    final devices = json['devices'];
    final rawReport = json['report'];
    if (id is! String ||
        !RegExp(r'^\d{10}$').hasMatch(id) ||
        building is! String ||
        latitude is! num ||
        longitude is! num ||
        status is! String ||
        devices is! List) {
      throw const FormatException('ข้อมูล ticket ไม่ครบถ้วน');
    }
    return WorkTicket(
      ticketId: id,
      building: building,
      area: _optionalString(json['area']),
      floor: _optionalString(json['floor']),
      room: _optionalString(json['room']),
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      status: status,
      devices: devices.map(WorkDevice.fromJson).toList(growable: false),
      report: rawReport == null ? null : WorkReport.fromJson(rawReport),
    );
  }
}

class WorkDevice {
  const WorkDevice({
    required this.deviceId,
    required this.rowIndex,
    required this.name,
    required this.description,
  });

  final int deviceId;
  final int rowIndex;
  final String? name;
  final String? description;

  factory WorkDevice.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('ข้อมูลอุปกรณ์ไม่ถูกต้อง');
    final json = Map<String, dynamic>.from(value);
    final id = json['deviceid'];
    final rowIndex = json['row_index'];
    if (id is! num ||
        !id.isFinite ||
        id != id.truncateToDouble() ||
        rowIndex is! num ||
        !rowIndex.isFinite ||
        rowIndex != rowIndex.truncateToDouble()) {
      throw const FormatException('รหัสอุปกรณ์ไม่ถูกต้อง');
    }
    return WorkDevice(
      deviceId: id.toInt(),
      rowIndex: rowIndex.toInt(),
      name: _optionalString(json['device']),
      description: _optionalString(json['discription']),
    );
  }
}

class WorkReport {
  const WorkReport({
    required this.id,
    required this.outcome,
    required this.status,
    required this.comment,
    required this.submittedAt,
    required this.photoUrl,
    required this.deviceResults,
  });

  final String id;
  final String outcome;
  final String status;
  final String? comment;
  final String submittedAt;
  final String? photoUrl;
  final List<ReportDeviceResult> deviceResults;

  factory WorkReport.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('ข้อมูลรายงานไม่ถูกต้อง');
    final json = Map<String, dynamic>.from(value);
    final id = json['id'];
    final outcome = json['outcome'];
    final status = json['status'];
    final submittedAt = json['submitted_at'];
    if (id is! String ||
        !{'success', 'failure'}.contains(outcome) ||
        !{'under_review', 'approved'}.contains(status) ||
        submittedAt is! String) {
      throw const FormatException('ข้อมูลรายงานไม่ครบถ้วน');
    }
    return WorkReport(
      id: id,
      outcome: outcome as String,
      status: status as String,
      comment: _optionalString(json['comment']),
      submittedAt: submittedAt,
      photoUrl: _optionalString(json['photoUrl']),
      deviceResults: _reportDeviceResults(json['deviceResults']),
    );
  }
}

class _ReviewReport {
  const _ReviewReport({
    required this.id,
    required this.ticketId,
    required this.building,
    required this.area,
    required this.floor,
    required this.room,
    required this.technicianName,
    required this.outcome,
    required this.comment,
    required this.submittedAt,
    required this.photoUrl,
    required this.deviceResults,
  });

  final String id;
  final String ticketId;
  final String building;
  final String? area;
  final String? floor;
  final String? room;
  final String technicianName;
  final String outcome;
  final String? comment;
  final String submittedAt;
  final String? photoUrl;
  final List<ReportDeviceResult> deviceResults;

  factory _ReviewReport.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('ข้อมูลรายงานไม่ถูกต้อง');
    final json = Map<String, dynamic>.from(value);
    final id = json['id'];
    final ticketId = json['TicketId'];
    final building = json['building'];
    final technicianName = json['technicianName'];
    final outcome = json['outcome'];
    final submittedAt = json['submitted_at'];
    if (id is! String ||
        ticketId is! String ||
        !RegExp(r'^\d{10}$').hasMatch(ticketId) ||
        building is! String ||
        technicianName is! String ||
        !{'success', 'failure'}.contains(outcome) ||
        submittedAt is! String) {
      throw const FormatException('ข้อมูลรายงานไม่ครบถ้วน');
    }
    return _ReviewReport(
      id: id,
      ticketId: ticketId,
      building: building,
      area: _optionalString(json['area']),
      floor: _optionalString(json['floor']),
      room: _optionalString(json['room']),
      technicianName: technicianName,
      outcome: outcome as String,
      comment: _optionalString(json['comment']),
      submittedAt: submittedAt,
      photoUrl: _optionalString(json['photoUrl']),
      deviceResults: _reportDeviceResults(json['deviceResults']),
    );
  }
}

class ReportDeviceResult {
  const ReportDeviceResult({
    required this.deviceId,
    required this.rowIndex,
    required this.success,
    required this.photoUrl,
  });

  final int deviceId;
  final int rowIndex;
  final bool success;
  final String? photoUrl;
}

List<ReportDeviceResult> _reportDeviceResults(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('ผลรายอุปกรณ์ไม่ถูกต้อง');
  return value
      .map((entry) {
        if (entry is! Map ||
            entry['deviceid'] is! int ||
            entry['row_index'] is! int ||
            entry['success'] is! bool ||
            (entry['photoUrl'] != null && entry['photoUrl'] is! String)) {
          throw const FormatException('ผลรายอุปกรณ์ไม่ครบถ้วน');
        }
        return ReportDeviceResult(
          deviceId: entry['deviceid'] as int,
          rowIndex: entry['row_index'] as int,
          success: entry['success'] as bool,
          photoUrl: _optionalString(entry['photoUrl']),
        );
      })
      .toList(growable: false);
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _ReportStatusChip extends StatelessWidget {
  const _ReportStatusChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

Future<void> _showMap(BuildContext context, WorkTicket ticket) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('ตำแหน่ง Ticket ${ticket.ticketId}'),
      content: SizedBox(
        width: 620,
        height: 400,
        child: Column(
          children: [
            Expanded(
              child: flutter_map.FlutterMap(
                options: flutter_map.MapOptions(
                  initialCenter: latlong.LatLng(
                    ticket.latitude,
                    ticket.longitude,
                  ),
                  initialZoom: 16,
                ),
                children: [
                  flutter_map.TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.mobileproject',
                  ),
                  flutter_map.MarkerLayer(
                    markers: [
                      flutter_map.Marker(
                        point: latlong.LatLng(
                          ticket.latitude,
                          ticket.longitude,
                        ),
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Latitude ${ticket.latitude.toStringAsFixed(6)} · '
              'Longitude ${ticket.longitude.toStringAsFixed(6)}',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}

Future<void> _showImage(
  BuildContext context,
  String ticketId,
  String photoUrl,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('รูปผลลัพธ์ Ticket $ticketId'),
      content: SizedBox(
        width: 640,
        height: 480,
        child: Image.network(
          photoUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Center(child: Text('โหลดรูปไม่สำเร็จ กรุณาโหลดรายการใหม่')),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('ข้อมูลข้อความไม่ถูกต้อง');
  return value;
}

String _formatDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
}
