import 'dart:async';

import 'package:flutter/material.dart';

import '../database/connect.dart';

class TicketMonitor extends StatefulWidget {
  const TicketMonitor({super.key});

  @override
  State<TicketMonitor> createState() => _TicketMonitorState();
}

class _TicketMonitorState extends State<TicketMonitor> {
  static const _pageSize = 10;
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  List<_Ticket> _tickets = const [];
  int _page = 0;
  int _total = 0;
  int _requestVersion = 0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchTimer?.cancel();
    _requestVersion++;
    setState(() {
      _page = 0;
      _tickets = const [];
      _isLoading = true;
      _errorMessage = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 350), _loadTickets);
  }

  Future<void> _loadTickets() async {
    _searchTimer?.cancel();
    final requestVersion = ++_requestVersion;
    if (!SupabaseConnection.isInitialized) {
      setState(() {
        _tickets = const [];
        _total = 0;
        _isLoading = false;
        _errorMessage = 'ยังไม่ได้เชื่อมต่อ Supabase';
      });
      return;
    }
    final ticketId = _searchController.text.trim();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'list-public-tickets',
        body: {'ticketId': ticketId, 'page': _page, 'pageSize': _pageSize},
      );
      final data = response.data;
      if (data is! Map || data['tickets'] is! List || data['total'] is! int) {
        throw const FormatException('รูปแบบข้อมูลรายการ Ticket ไม่ถูกต้อง');
      }
      final tickets = (data['tickets'] as List)
          .map(_Ticket.fromJson)
          .toList(growable: false);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _tickets = tickets;
        _total = data['total'] as int;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _tickets = const [];
        _total = 0;
        _isLoading = false;
        _errorMessage = 'โหลดรายการ Ticket ไม่สำเร็จ: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = (_total / _pageSize).ceil();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ติดตามงานซ่อม',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'ค้นหา TicketId',
              hintText: 'กรอก TicketId',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'ล้างคำค้นหา',
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
            textAlignVertical: TextAlignVertical.center,
            keyboardType: TextInputType.number,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _loadTickets(),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildTable(context)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _total == 0
                    ? 'ไม่พบรายการ'
                    : 'หน้า ${_page + 1} จาก $pageCount  •  $_total รายการ',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'หน้าก่อนหน้า',
                onPressed: _isLoading || _page == 0
                    ? null
                    : () {
                        setState(() => _page--);
                        _loadTickets();
                      },
                icon: const Icon(Icons.chevron_left),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'หน้าถัดไป',
                onPressed: _isLoading || _page + 1 >= pageCount
                    ? null
                    : () {
                        setState(() => _page++);
                        _loadTickets();
                      },
                icon: const Icon(Icons.chevron_right),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loadTickets,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองอีกครั้ง'),
            ),
          ],
        ),
      );
    }
    if (_tickets.isEmpty) {
      return const Center(child: Text('ไม่พบ Ticket ที่ค้นหา'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 720
            ? 720.0
            : constraints.maxWidth;
        final colors = Theme.of(context).colorScheme;
        final borderColor = colors.outlineVariant.withValues(alpha: 0.55);
        final columnWidth = tableWidth / 7;
        final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        );
        final cellStyle = Theme.of(context).textTheme.bodyMedium;

        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              width: tableWidth,
              decoration: BoxDecoration(
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(12),
                color: colors.surface,
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Table(
                    columnWidths: {
                      for (var index = 0; index < 7; index++)
                        index: FixedColumnWidth(columnWidth),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder(
                      verticalInside: BorderSide(
                        color: borderColor,
                        width: 0.7,
                      ),
                      bottom: BorderSide(color: borderColor, width: 0.7),
                    ),
                    children: [
                      TableRow(
                        children: [
                          for (final label in const [
                            'TicketId',
                            'อาคาร',
                            'บริเวณ',
                            'ชั้นที่',
                            'เลขห้อง',
                            'วันเข้าซ่อม',
                            'สถานะ',
                          ])
                            _tableCell(
                              label,
                              backgroundColor: colors.primaryContainer
                                  .withValues(alpha: 0.55),
                              textStyle: headingStyle,
                            ),
                        ],
                      ),
                    ],
                  ),
                  for (var index = 0; index < _tickets.length; index++)
                    _ExpandableTicketRow(
                      key: ValueKey(_tickets[index].ticketId),
                      ticket: _tickets[index],
                      index: index,
                      columnWidth: columnWidth,
                      borderColor: borderColor,
                      textStyle: cellStyle,
                      tableCell: _tableCell,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableCell(
    String text, {
    required Color backgroundColor,
    TextStyle? textStyle,
    Widget? child,
  }) {
    return Container(
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      color: backgroundColor,
      child:
          child ??
          Text(
            text,
            textAlign: TextAlign.center,
            style: textStyle,
            overflow: TextOverflow.ellipsis,
          ),
    );
  }
}

class _ExpandableTicketRow extends StatefulWidget {
  const _ExpandableTicketRow({
    super.key,
    required this.ticket,
    required this.index,
    required this.columnWidth,
    required this.borderColor,
    required this.textStyle,
    required this.tableCell,
  });

  final _Ticket ticket;
  final int index;
  final double columnWidth;
  final Color borderColor;
  final TextStyle? textStyle;
  final Widget Function(
    String text, {
    required Color backgroundColor,
    TextStyle? textStyle,
    Widget? child,
  })
  tableCell;

  @override
  State<_ExpandableTicketRow> createState() => _ExpandableTicketRowState();
}

class _ExpandableTicketRowState extends State<_ExpandableTicketRow> {
  bool _isExpanded = false;
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  List<_TicketDevice> _devices = const [];

  Future<void> _toggleExpanded() async {
    final willExpand = !_isExpanded;
    setState(() => _isExpanded = willExpand);
    if (!willExpand || _hasLoaded || _isLoading) return;

    await _loadDevices();
  }

  Future<void> _loadDevices() async {
    if (_isLoading) return;
    if (!SupabaseConnection.isInitialized) {
      setState(() => _errorMessage = 'ยังไม่ได้เชื่อมต่อ Supabase');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'list-public-tickets',
        body: {'action': 'devices', 'ticketId': widget.ticket.ticketId},
      );
      final data = response.data;
      if (data is! Map || data['devices'] is! List) {
        throw const FormatException('รูปแบบข้อมูลอุปกรณ์ไม่ถูกต้อง');
      }
      final devices = (data['devices'] as List)
          .map(_TicketDevice.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _hasLoaded = true;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'โหลดรายการอุปกรณ์ไม่สำเร็จ: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rowColor = widget.index.isEven
        ? colors.surface
        : colors.surfaceContainerLowest;

    return Column(
      children: [
        InkWell(
          onTap: _toggleExpanded,
          child: Table(
            columnWidths: {
              for (var index = 0; index < 7; index++)
                index: FixedColumnWidth(widget.columnWidth),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(
              verticalInside: BorderSide(color: widget.borderColor, width: 0.7),
              bottom: BorderSide(color: widget.borderColor, width: 0.7),
            ),
            children: [
              TableRow(
                children: [
                  widget.tableCell(
                    widget.ticket.ticketId,
                    backgroundColor: rowColor,
                    textStyle: widget.textStyle?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  widget.tableCell(
                    widget.ticket.building,
                    backgroundColor: rowColor,
                    textStyle: widget.textStyle,
                  ),
                  widget.tableCell(
                    widget.ticket.area ?? 'อาคาร ${widget.ticket.building}',
                    backgroundColor: rowColor,
                    textStyle: widget.textStyle,
                  ),
                  widget.tableCell(
                    widget.ticket.floor ?? 'ไม่ระบุ',
                    backgroundColor: rowColor,
                    textStyle: widget.textStyle,
                  ),
                  widget.tableCell(
                    widget.ticket.room ?? 'ไม่ระบุ',
                    backgroundColor: rowColor,
                    textStyle: widget.textStyle,
                  ),
                  widget.tableCell(
                    widget.ticket.nextFixDate == null
                        ? 'ยังไม่มีกำหนด'
                        : _formatNextFixDate(widget.ticket.nextFixDate!),
                    backgroundColor: rowColor,
                    textStyle: widget.textStyle,
                  ),
                  widget.tableCell(
                    '',
                    backgroundColor: rowColor,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.ticket.status,
                            style: TextStyle(
                              color: colors.onSecondaryContainer,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_isExpanded) _buildDevicesPanel(context, rowColor),
      ],
    );
  }

  Widget _buildDevicesPanel(BuildContext context, Color rowColor) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: widget.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'อุปกรณ์ย่อย',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage case final error?)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(error),
                TextButton.icon(
                  onPressed: _loadDevices,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองอีกครั้ง'),
                ),
              ],
            )
          else if (_devices.isEmpty)
            const Text('ไม่มีรายการอุปกรณ์ย่อย')
          else
            _buildDevicesTable(context),
        ],
      ),
    );
  }

  Widget _buildDevicesTable(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final headings = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final values = Theme.of(context).textTheme.bodyMedium;
    final deviceColumnWidth = widget.columnWidth * 1.1;
    final detailColumnWidth = widget.columnWidth * 2.6;
    final statusColumnWidth = widget.columnWidth * 1.6;

    return Table(
      columnWidths: {
        0: FixedColumnWidth(widget.columnWidth * 0.7),
        1: FixedColumnWidth(deviceColumnWidth),
        2: FixedColumnWidth(detailColumnWidth),
        3: FixedColumnWidth(statusColumnWidth),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: widget.borderColor, width: 0.7),
      ),
      children: [
        TableRow(
          children: [
            for (final label in const [
              'ลำดับ',
              'อุปกรณ์',
              'รายละเอียด',
              'สถานะ',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                child: Text(label, style: headings),
              ),
          ],
        ),
        for (final device in _devices)
          TableRow(
            children: [
              _deviceCell(device.deviceId.toString(), values),
              _deviceCell(device.name, values),
              _deviceCell(device.description ?? '-', values),
              _deviceCell(device.status, values),
            ],
          ),
      ],
    );
  }

  String _formatNextFixDate(DateTime dateTime) {
    final localDateTime = dateTime.toLocal();
    final day = localDateTime.day.toString().padLeft(2, '0');
    final month = localDateTime.month.toString().padLeft(2, '0');
    final hour = localDateTime.hour.toString().padLeft(2, '0');
    final minute = localDateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/${localDateTime.year} $hour:$minute';
  }

  Widget _deviceCell(String text, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(text, style: style),
    );
  }
}

class _Ticket {
  const _Ticket({
    required this.ticketId,
    required this.building,
    required this.area,
    required this.floor,
    required this.room,
    required this.nextFixDate,
    required this.status,
  });

  final String ticketId;
  final String building;
  final String? area;
  final String? floor;
  final String? room;
  final DateTime? nextFixDate;
  final String status;

  factory _Ticket.fromJson(dynamic value) {
    if (value is! Map ||
        value['TicketId'] is! String ||
        value['building'] is! String ||
        value['status'] is! String ||
        (value['area'] != null && value['area'] is! String) ||
        (value['floor'] != null && value['floor'] is! String) ||
        (value['room'] != null && value['room'] is! String) ||
        (value['next_fix_date'] != null && value['next_fix_date'] is! String)) {
      throw const FormatException('ข้อมูล Ticket ไม่ครบถ้วน');
    }
    final nextFixDateValue = value['next_fix_date'] as String?;
    final nextFixDate = nextFixDateValue == null
        ? null
        : DateTime.tryParse(nextFixDateValue);
    if (nextFixDateValue != null && nextFixDate == null) {
      throw const FormatException('รูปแบบวันเข้าซ่อมไม่ถูกต้อง');
    }
    return _Ticket(
      ticketId: value['TicketId'] as String,
      building: value['building'] as String,
      area: value['area'] as String?,
      floor: value['floor'] as String?,
      room: value['room'] as String?,
      nextFixDate: nextFixDate,
      status: value['status'] as String,
    );
  }
}

class _TicketDevice {
  const _TicketDevice({
    required this.deviceId,
    required this.name,
    required this.description,
    required this.status,
  });

  final int deviceId;
  final String name;
  final String? description;
  final String status;

  factory _TicketDevice.fromJson(dynamic value) {
    if (value is! Map ||
        value['deviceid'] is! int ||
        value['device'] is! String ||
        value['status'] is! String ||
        (value['discription'] != null && value['discription'] is! String)) {
      throw const FormatException('ข้อมูลอุปกรณ์ไม่ครบถ้วน');
    }
    return _TicketDevice(
      deviceId: value['deviceid'] as int,
      name: value['device'] as String,
      description: value['discription'] as String?,
      status: value['status'] as String,
    );
  }
}
