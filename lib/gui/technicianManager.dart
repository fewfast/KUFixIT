import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';

class TechnicianManagerPage extends StatefulWidget {
  const TechnicianManagerPage({super.key});

  @override
  State<TechnicianManagerPage> createState() => _TechnicianManagerPageState();
}

class _TechnicianManagerPageState extends State<TechnicianManagerPage> {
  final _technicianNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _commentController = TextEditingController();
  List<_Technician> _technicians = [];
  bool _isLoadingTechnicians = true;
  bool _isCreatingTechnician = false;
  String? _techniciansError;
  String? _operationError;
  String _searchQuery = '';
  bool _showPasswords = false;

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  @override
  void dispose() {
    _technicianNameController.dispose();
    _usernameController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, Object?> body = const {},
  ]) async {
    final account = TemporaryAccountSession.instance.account;
    if (account == null) {
      throw Exception('เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
    }
    if (!SupabaseConnection.isInitialized) {
      throw Exception('ยังไม่ได้เชื่อมต่อ Supabase');
    }
    late final Object? responseData;
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'maintenance-teams',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {'action': action, ...body},
      );
      responseData = response.data;
    } catch (error) {
      throw Exception(
        functionErrorMessage(error, 'เรียกบริการจัดการช่างไม่สำเร็จ'),
      );
    }
    if (responseData is! Map) {
      throw const FormatException('รูปแบบข้อมูลจากระบบจัดการช่างไม่ถูกต้อง');
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

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoadingTechnicians = true;
      _techniciansError = null;
    });
    try {
      final data = await _invoke('list-technicians');
      final rawTechnicians = data['technicians'];
      if (rawTechnicians is! List) {
        throw const FormatException('ไม่พบรายการช่างในข้อมูลตอบกลับ');
      }
      final technicians = rawTechnicians
          .map(_Technician.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _technicians = technicians;
        _isLoadingTechnicians = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _techniciansError = _errorText(error);
        _isLoadingTechnicians = false;
      });
    }
  }

  Future<void> _createTechnician() async {
    final teamName = _technicianNameController.text.trim();
    final username = _usernameController.text.trim();
    final comment = _commentController.text.trim();
    if (teamName.isEmpty) {
      setState(() => _operationError = 'กรุณากรอกชื่อช่าง');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_]{3,64}$').hasMatch(username)) {
      setState(
        () => _operationError =
            'username ต้องมี 3-64 ตัวอักษร และใช้ได้เฉพาะ A-Z, a-z, 0-9 หรือ _',
      );
      return;
    }
    if (comment.isEmpty) {
      setState(() => _operationError = 'กรุณากรอกข้อมูลช่าง');
      return;
    }
    if (comment.length > 1000) {
      setState(() => _operationError = 'ข้อมูลช่างต้องไม่เกิน 1,000 ตัวอักษร');
      return;
    }
    setState(() {
      _isCreatingTechnician = true;
      _operationError = null;
    });
    try {
      final data = await _invoke('create-technician', {
        'teamName': teamName,
        'username': username,
        'comment': comment,
      });
      final uid = data['uid'];
      final createdUsername = data['username'];
      final password = data['password'];
      if (uid is! String ||
          !RegExp(r'^t_[0-9]{10}$').hasMatch(uid) ||
          createdUsername is! String ||
          password is! String ||
          password.length != 10) {
        throw const FormatException('ระบบสร้างบัญชีช่างส่งข้อมูลไม่ครบ');
      }
      _technicianNameController.clear();
      _usernameController.clear();
      _commentController.clear();
      await _loadTechnicians();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('สร้างบัญชีช่างเรียบร้อยแล้ว'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'บัญชีนี้ยัง login ไม่ได้จนกว่าจะกำหนดช่วงวันที่อนุญาต',
              ),
              const SizedBox(height: 12),
              SelectableText('UID: $uid'),
              SelectableText('ชื่อผู้ใช้: $createdUsername'),
              SelectableText('รหัสผ่าน: $password'),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _copyText('$uid\n$createdUsername\n$password'),
              icon: const Icon(Icons.copy),
              label: const Text('คัดลอกข้อมูล'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _operationError = _errorText(error));
    } finally {
      if (mounted) setState(() => _isCreatingTechnician = false);
    }
  }

  Future<void> _updateTechnician(
    _Technician technician,
    Map<String, Object?> changes,
  ) async {
    try {
      await _invoke('update-technician', {'uid': technician.uid, ...changes});
      await _loadTechnicians();
      _showMessage('บันทึกข้อมูลช่างเรียบร้อยแล้ว');
    } catch (error) {
      _showMessage('บันทึกข้อมูลช่างไม่สำเร็จ: ${_errorText(error)}');
    }
  }

  Future<void> _updateDateRanges(
    _Technician technician,
    List<_DateRange> ranges,
  ) async {
    final dateRanges = ranges
        .map(
          (range) => {
            'start': _encodeDate(range.start),
            'end': _encodeDate(range.end),
          },
        )
        .toList(growable: false);
    try {
      await _invoke('update-technician', {
        'uid': technician.uid,
        'dateRanges': dateRanges,
      });
      await _loadTechnicians();
      _showMessage('บันทึกช่วงวันที่เรียบร้อยแล้ว');
    } catch (error) {
      _showMessage('บันทึกช่วงวันที่ไม่สำเร็จ: ${_errorText(error)}');
    }
  }

  Future<void> _editTechnicianName(_Technician technician) async {
    final controller = TextEditingController(text: technician.teamName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขชื่อช่าง'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'ชื่อช่าง'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim() != technician.teamName) {
      final name = value.trim();
      if (name.isEmpty) {
        _showMessage('ชื่อช่างต้องไม่เว้นว่าง');
        return;
      }
      await _updateTechnician(technician, {'teamName': name});
    }
  }

  Future<void> _editDateRanges(_Technician technician) async {
    var ranges = technician.dateRanges.toList();
    final result = await showDialog<List<_DateRange>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('วันที่เข้าใช้งานได้'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ranges.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'ยังไม่ได้กำหนดช่วงวันที่ จึงยัง login ไม่ได้',
                      ),
                    ),
                  for (var i = 0; i < ranges.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final today = _todayInBangkok();
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: ranges[i].start.isBefore(today)
                                      ? today
                                      : ranges[i].start,
                                  firstDate: today,
                                  lastDate: DateTime(2100),
                                );
                                if (date == null) return;
                                setDialogState(() {
                                  ranges[i] = ranges[i].copyWith(
                                    start: date,
                                    end: ranges[i].end.isBefore(date)
                                        ? date
                                        : ranges[i].end,
                                  );
                                });
                              },
                              child: Text(
                                'เริ่ม ${_formatDateOnly(ranges[i].start)}',
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('-'),
                          ),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final firstDate =
                                    ranges[i].start.isBefore(_todayInBangkok())
                                    ? _todayInBangkok()
                                    : ranges[i].start;
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: ranges[i].end.isBefore(firstDate)
                                      ? firstDate
                                      : ranges[i].end,
                                  firstDate: firstDate,
                                  lastDate: DateTime(2100),
                                );
                                if (date == null) return;
                                setDialogState(() {
                                  ranges[i] = ranges[i].copyWith(end: date);
                                });
                              },
                              child: Text(
                                'สิ้นสุด ${_formatDateOnly(ranges[i].end)}',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'ลบช่วงวันที่',
                            onPressed: () =>
                                setDialogState(() => ranges.removeAt(i)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setDialogState(() {
                      final today = _todayInBangkok();
                      ranges.add(_DateRange(start: today, end: today));
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มช่วงวันที่'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, ranges),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await _updateDateRanges(technician, result);
  }

  String _encodeDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _formatDateOnly(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year + 543}';

  DateTime _todayInBangkok() {
    final bangkokNow = DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime(bangkokNow.year, bangkokNow.month, bangkokNow.day);
  }

  Future<void> _copyText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _showMessage('คัดลอกแล้ว');
    } catch (error) {
      if (mounted) _showMessage('คัดลอกไม่สำเร็จ: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year + 543} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  Widget _technicianTable(List<_Technician> technicians) {
    if (technicians.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('ไม่พบข้อมูลช่าง')),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('สร้างเมื่อ')),
          DataColumn(label: Text('ชื่อช่าง')),
          DataColumn(label: Text('UID ช่าง')),
          DataColumn(label: Text('ชื่อผู้ใช้')),
          DataColumn(label: Text('ข้อมูลช่าง')),
          DataColumn(label: Text('รหัสผ่าน')),
          DataColumn(label: Text('วันที่เข้าใช้งาน')),
        ],
        rows: [
          for (final technician in technicians)
            DataRow(
              cells: [
                DataCell(Text(_formatDate(technician.createdAt))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(technician.teamName),
                      IconButton(
                        tooltip: 'แก้ไขชื่อช่าง',
                        onPressed: () => _editTechnicianName(technician),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(technician.uid),
                      IconButton(
                        tooltip: 'คัดลอก UID ช่าง',
                        onPressed: () => _copyText(technician.uid),
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(technician.username),
                      IconButton(
                        tooltip: 'คัดลอกชื่อผู้ใช้',
                        onPressed: () => _copyText(technician.username),
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 200,
                    child: Tooltip(
                      message: technician.comment,
                      child: Text(
                        technician.comment.isEmpty ? '-' : technician.comment,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_showPasswords ? technician.password : '••••••••••'),
                      IconButton(
                        tooltip: _showPasswords
                            ? 'ซ่อนรหัสผ่าน'
                            : 'แสดงรหัสผ่าน',
                        onPressed: () =>
                            setState(() => _showPasswords = !_showPasswords),
                        icon: Icon(
                          _showPasswords
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: 'คัดลอกรหัสผ่าน',
                        onPressed: () => _copyText(technician.password),
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 230,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            technician.dateRanges.isEmpty
                                ? 'ไม่กำหนด'
                                : technician.dateRanges
                                      .map(
                                        (range) =>
                                            '${_formatDateOnly(range.start)}-${_formatDateOnly(range.end)}',
                                      )
                                      .join(', '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'แก้ไขช่วงวันที่',
                          onPressed: () => _editDateRanges(technician),
                          icon: const Icon(Icons.edit_calendar_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = TemporaryAccountSession.instance.account;
    if (account == null ||
        (account.role != 'Admin' && account.role != 'SuperAdmin')) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('จัดการบัญชีและข้อมูลช่างเทคนิค'),
            SizedBox(height: 8),
            Text('หน้านี้สำหรับผู้ดูแลระบบเท่านั้น'),
          ],
        ),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final visibleTechnicians = _technicians
        .where((technician) {
          if (query.isEmpty) return true;
          return technician.teamName.toLowerCase().contains(query) ||
              technician.username.toLowerCase().contains(query) ||
              technician.uid.toLowerCase().contains(query) ||
              technician.comment.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.all(constraints.maxWidth < 600 ? 12 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'จัดการช่างเทคนิค',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'สร้างผู้ใช้ช่าง',
                  subtitle:
                      'กำหนดชื่อช่าง username และข้อมูลช่าง ระบบจะสร้าง UID และรหัสผ่านให้',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _technicianNameController,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อช่าง',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _usernameController,
                        maxLength: 64,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'username ช่าง',
                          helperText:
                              'ใช้ตัวอักษรอังกฤษ ตัวเลข หรือ _ (3-64 ตัว)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        maxLength: 1000,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'ข้อมูลช่าง *',
                          helperText: 'จำเป็นต้องกรอก',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _isCreatingTechnician
                            ? null
                            : _createTechnician,
                        icon: _isCreatingTechnician
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: const Text('สร้างบัญชีช่าง'),
                      ),
                      if (_operationError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _operationError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _sectionCard(
                  title: 'รายการช่างทั้งหมด',
                  subtitle: 'ค้นหาด้วยชื่อช่าง username UID หรือข้อมูลช่าง',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'ค้นหาช่าง',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingTechnicians)
                        const LinearProgressIndicator()
                      else if (_techniciansError != null)
                        _errorMessage(_techniciansError!, _loadTechnicians)
                      else
                        _technicianTable(visibleTechnicians),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorMessage(String message, VoidCallback onRetry) => Row(
    children: [
      Expanded(child: Text(message)),
      IconButton(
        tooltip: 'ลองอีกครั้ง',
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
      ),
    ],
  );
}

class _Technician {
  const _Technician({
    required this.uid,
    required this.createdAt,
    required this.teamName,
    required this.username,
    required this.comment,
    required this.password,
    required this.dateRanges,
  });

  final String uid;
  final DateTime createdAt;
  final String teamName;
  final String username;
  final String comment;
  final String password;
  final List<_DateRange> dateRanges;

  factory _Technician.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('ข้อมูลบัญชีช่างไม่ถูกต้อง');
    final data = Map<String, Object?>.from(value);
    final uid = data['uid'];
    final createdAt = data['created_at'];
    final teamName = data['teamName'];
    final username = data['username'];
    final comment = data['comment'];
    final password = data['password'];
    final starts = data['start_time'];
    final ends = data['end_time'];
    if (uid is! String ||
        createdAt is! String ||
        teamName is! String ||
        username is! String ||
        comment is! String ||
        password is! String ||
        starts is! List ||
        ends is! List ||
        starts.length != ends.length) {
      throw const FormatException('ข้อมูลบัญชีช่างไม่ครบถ้วน');
    }
    final ranges = <_DateRange>[];
    for (var i = 0; i < starts.length; i++) {
      ranges.add(
        _DateRange(start: _parseDate(starts[i]), end: _parseDate(ends[i])),
      );
    }
    return _Technician(
      uid: uid,
      createdAt: DateTime.parse(createdAt).toLocal(),
      teamName: teamName,
      username: username,
      comment: comment,
      password: password,
      dateRanges: ranges,
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is! String) {
      throw const FormatException('รูปแบบวันที่ไม่ถูกต้อง');
    }
    final bangkokDate = DateTime.parse(
      value,
    ).toUtc().add(const Duration(hours: 7));
    return DateTime(bangkokDate.year, bangkokDate.month, bangkokDate.day);
  }
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  _DateRange copyWith({DateTime? start, DateTime? end}) =>
      _DateRange(start: start ?? this.start, end: end ?? this.end);
}
