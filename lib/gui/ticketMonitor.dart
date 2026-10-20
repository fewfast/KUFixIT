import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart' as latlong;
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';
import '../database/realtime_invalidation.dart';
import 'building_locations.dart';
import 'ticket_schedule_serialization.dart';
import 'ticket_load_error_message.dart';
import 'ticket_update_error_message.dart';

const _ticketLocationMapCenter = latlong.LatLng(13.1209646, 100.9192182);

typedef FetchTicketsFn = Future<Map<String, dynamic>> Function({
  required bool myRequests,
  required bool adminMode,
  required String ticketId,
  required int page,
  required int pageSize,
  required String sortBy,
  required bool sortAscending,
});

typedef FetchTicketDevicesFn = Future<Map<String, dynamic>> Function(
  String ticketId,
);

class TicketMonitor extends StatefulWidget {
  const TicketMonitor({
    super.key,
    this.myRequests = false,
    this.adminMode = false,
    this.fetchTickets,
    this.fetchDevices,
  });

  final bool myRequests;
  final bool adminMode;
  final FetchTicketsFn? fetchTickets;
  final FetchTicketDevicesFn? fetchDevices;

  @override
  State<TicketMonitor> createState() => _TicketMonitorState();
}

class _TicketMonitorState extends State<TicketMonitor> {
  static const _pageSize = 10;
  final _searchController = TextEditingController();
  final _ticketsScrollController = ScrollController();
  Timer? _searchTimer;
  List<_Ticket> _tickets = const [];
  int _page = 0;
  int _total = 0;
  int _requestVersion = 0;
  String _sortColumn = 'status';
  bool _sortAscending = true;
  static const _statusOrder = {
    'pending': 0,
    'validating': 1,
    'finish': 2,
    'rejected': 3,
    'cancel': 4,
  };
  bool _isLoading = true;
  String? _errorMessage;
  TicketLoadErrorInfo? _errorInfo;
  bool _showErrorDetails = false;
  late final RealtimeRefreshBinding _realtimeRefresh;

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
      onRefresh: _loadTickets,
      isMounted: () => mounted,
    );
    _loadTickets();
  }

  @override
  void dispose() {
    _realtimeRefresh.dispose();
    _searchTimer?.cancel();
    _searchController.dispose();
    _ticketsScrollController.dispose();
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
      _errorInfo = null;
      _showErrorDetails = false;
    });
    _searchTimer = Timer(const Duration(milliseconds: 350), _loadTickets);
  }

  void _sortBy(String column) {
    setState(() {
      if (_sortColumn != column) {
        _sortColumn = column;
        _sortAscending = true;
      } else if (_sortAscending) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = 'status';
        _sortAscending = true;
      }
      _page = 0;
      _tickets = _sortTickets(_tickets);
    });
    _loadTickets();
  }

  List<_Ticket> _sortTickets(List<_Ticket> tickets) {
    final sorted = [...tickets];
    final originalOrder = {
      for (var index = 0; index < tickets.length; index++)
        tickets[index].ticketId: index,
    };
    sorted.sort((first, second) {
      final firstValue = _ticketSortValue(first, _sortColumn);
      final secondValue = _ticketSortValue(second, _sortColumn);
      int result;
      if (firstValue == null || secondValue == null) {
        if (firstValue == null && secondValue != null) return 1;
        if (firstValue != null && secondValue == null) return -1;
        result = 0;
      } else if (firstValue is DateTime && secondValue is DateTime) {
        result = firstValue.compareTo(secondValue);
      } else if (firstValue is DateTime && secondValue is String) {
        result = firstValue.compareTo(DateTime.parse(secondValue));
      } else if (firstValue is String && secondValue is DateTime) {
        result = DateTime.parse(firstValue).compareTo(secondValue);
      } else if (firstValue is int && secondValue is int) {
        result = firstValue.compareTo(secondValue);
      } else {
        result = firstValue.toString().toLowerCase().compareTo(
          secondValue.toString().toLowerCase(),
        );
      }
      if (result == 0) {
        return originalOrder[first.ticketId]!.compareTo(
          originalOrder[second.ticketId]!,
        );
      }
      return _sortAscending ? result : -result;
    });
    return sorted;
  }

  Object? _ticketSortValue(_Ticket ticket, String column) {
    return switch (column) {
      'TicketId' => ticket.ticketId,
      'request_date' => ticket.requestDate,
      'building' => ticket.building,
      'area' => ticket.area,
      'floor' => ticket.floor,
      'room' => ticket.room,
      'next_fix_date' => ticket.nextFixDateStart,
      'status' => _statusOrder[ticket.status] ?? 99,
      _ => null,
    };
  }

  Future<void> _loadTickets() async {
    _searchTimer?.cancel();
    final requestVersion = ++_requestVersion;
    final account = TemporaryAccountSession.instance.account;
    if ((widget.myRequests || widget.adminMode) &&
        account == null &&
        widget.fetchTickets == null) {
      setState(() {
        _tickets = const [];
        _total = 0;
        _isLoading = false;
        _errorMessage = widget.adminMode
            ? 'กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลระบบ'
            : 'กรุณาเข้าสู่ระบบเพื่อดูรายการแจ้งซ่อมของคุณ';
        _errorInfo = null;
      });
      return;
    }
    if (!SupabaseConnection.isInitialized && widget.fetchTickets == null) {
      setState(() {
        _tickets = const [];
        _total = 0;
        _isLoading = false;
        _errorMessage = 'ยังไม่ได้เชื่อมต่อ Supabase';
        _errorInfo = null;
      });
      return;
    }
    final ticketId = _searchController.text.trim();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorInfo = null;
      _showErrorDetails = false;
    });

    try {
      final Map<String, dynamic> data;
      if (widget.fetchTickets != null) {
        data = await widget.fetchTickets!(
          myRequests: widget.myRequests,
          adminMode: widget.adminMode,
          ticketId: ticketId,
          page: _page,
          pageSize: _pageSize,
          sortBy: _sortColumn,
          sortAscending: _sortAscending,
        );
      } else {
        final response = await SupabaseConnection.client.functions.invoke(
          'list-public-tickets',
          headers: widget.myRequests || widget.adminMode
              ? {'Authorization': 'Bearer ${account!.accessToken}'}
              : null,
          body: {
            if (widget.myRequests) 'action': 'my-tickets',
            if (widget.adminMode) 'action': 'admin-tickets',
            'ticketId': ticketId,
            'page': _page,
            'pageSize': _pageSize,
            'sortBy': _sortColumn,
            'sortAscending': _sortAscending,
          },
        );
        final responseData = response.data;
        if (responseData is! Map) {
          throw const FormatException('รูปแบบข้อมูลรายการ Ticket ไม่ถูกต้อง');
        }
        data = Map<String, dynamic>.from(responseData);
      }
      if (data['tickets'] is! List || data['total'] is! int) {
        throw const FormatException('รูปแบบข้อมูลรายการ Ticket ไม่ถูกต้อง');
      }
      final tickets = (data['tickets'] as List)
          .map((item) => _Ticket.fromJson(item as Map))
          .toList(growable: false);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _tickets = _sortTickets(tickets);
        _total = data['total'] as int;
        _isLoading = false;
        _errorInfo = null;
        _showErrorDetails = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _tickets = const [];
        _total = 0;
        _isLoading = false;
        _errorInfo = formatTicketLoadError(error);
        _showErrorDetails = false;
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
          Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text(
                  widget.myRequests ? 'รายการแจ้งซ่อมของฉัน' : 'ติดตามงานซ่อม',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: widget.adminMode
                  ? 'ค้นหา TicketId, UID หรือชื่อผู้ส่งคำร้อง'
                  : 'ค้นหา TicketId',
              hintText: widget.adminMode
                  ? 'กรอก TicketId, UID หรือชื่อผู้ส่งคำร้อง'
                  : 'กรอก TicketId',
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
            keyboardType:
                widget.adminMode ? TextInputType.text : TextInputType.number,
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
    if (_isLoading && _tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorInfo case final errorInfo?) {
      final colors = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 0,
              color: colors.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (errorInfo.isNetworkError
                                ? colors.errorContainer
                                : colors.secondaryContainer)
                            .withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        errorInfo.isNetworkError
                            ? Icons.wifi_off_rounded
                            : Icons.cloud_off_rounded,
                        size: 48,
                        color: errorInfo.isNetworkError
                            ? colors.error
                            : colors.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      errorInfo.title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      errorInfo.message,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _loadTickets,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_isLoading ? 'กำลังโหลด...' : 'ลองใหม่อีกครั้ง'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    if (errorInfo.rawDetails.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _showErrorDetails = !_showErrorDetails;
                        }),
                        icon: Icon(
                          _showErrorDetails
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 18,
                        ),
                        label: Text(
                          _showErrorDetails
                              ? 'ซ่อนรายละเอียดทางเทคนิค'
                              : 'ดูรายละเอียดข้อผิดพลาด',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (_showErrorDetails) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  colors.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: SelectableText(
                            errorInfo.rawDetails,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_errorMessage case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text(error, textAlign: TextAlign.center)],
        ),
      );
    }
    if (_tickets.isEmpty) {
      return const Center(child: Text('ไม่พบ Ticket ที่ค้นหา'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 940
            ? 940.0
            : constraints.maxWidth;
        final colors = Theme.of(context).colorScheme;
        final borderColor = colors.outlineVariant.withValues(alpha: 0.55);
        final columnWidth = tableWidth / 9.0;
        final scheduleColumnWidth = columnWidth * 1.2;
        final statusColumnWidth = columnWidth * 1.8;
        final headingStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        );
        final cellStyle = Theme.of(context).textTheme.bodyMedium;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            width: tableWidth,
            height: constraints.maxHeight,
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
                    for (var index = 0; index < 6; index++)
                      index: FixedColumnWidth(columnWidth),
                    6: FixedColumnWidth(scheduleColumnWidth),
                    7: FixedColumnWidth(statusColumnWidth),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder(
                    verticalInside: BorderSide(color: borderColor, width: 0.7),
                    bottom: BorderSide(color: borderColor, width: 0.7),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: colors.primaryContainer),
                      children: [
                        _sortableHeader(
                          'TicketId',
                          'TicketId',
                          backgroundColor: Colors.transparent,
                          textStyle: headingStyle,
                        ),
                        _sortableHeader(
                          'request_date',
                          'วันที่แจ้ง',
                          backgroundColor: Colors.transparent,
                          textStyle: headingStyle,
                        ),
                        for (final label in const [
                          'อาคาร',
                          'บริเวณ',
                          'ชั้นที่',
                          'เลขห้อง',
                        ])
                          _tableCell(
                            label,
                            backgroundColor: Colors.transparent,
                            textStyle: headingStyle,
                          ),
                        _sortableHeader(
                          'next_fix_date',
                          'ช่วงเวลาที่เข้าซ่อมครั้งถัดไป',
                          backgroundColor: Colors.transparent,
                          textStyle: headingStyle,
                        ),
                        _tableCell(
                          'สถานะ',
                          backgroundColor: Colors.transparent,
                          textStyle: headingStyle,
                        ),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: ScrollbarTheme(
                    data: const ScrollbarThemeData(
                      crossAxisMargin: 0,
                      mainAxisMargin: 0,
                    ),
                    child: Scrollbar(
                      controller: _ticketsScrollController,
                      scrollbarOrientation: ScrollbarOrientation.right,
                      child: CustomScrollView(
                        controller: _ticketsScrollController,
                        slivers: [
                          for (var index = 0; index < _tickets.length; index++)
                            _ExpandableTicketRow(
                              key: ValueKey(_tickets[index].ticketId),
                              ticket: _tickets[index],
                              myRequests: widget.myRequests,
                              adminMode: widget.adminMode,
                              fetchDevices: widget.fetchDevices,
                              onTicketCancelled: _loadTickets,
                              index: index,
                              columnWidth: columnWidth,
                              scheduleColumnWidth: scheduleColumnWidth,
                              statusColumnWidth: statusColumnWidth,
                              borderColor: borderColor,
                              textStyle: cellStyle,
                              tableCell: _tableCell,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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

  Widget _sortableHeader(
    String column,
    String label, {
    required Color backgroundColor,
    TextStyle? textStyle,
  }) {
    final isSorted = _sortColumn == column;
    return _tableCell(
      '',
      backgroundColor: backgroundColor,
      child: InkWell(
        onTap: () => _sortBy(column),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: textStyle,
                softWrap: true,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              isSorted
                  ? _sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward
                  : Icons.unfold_more,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableTicketRow extends StatefulWidget {
  const _ExpandableTicketRow({
    super.key,
    required this.ticket,
    required this.myRequests,
    required this.adminMode,
    this.fetchDevices,
    required this.onTicketCancelled,
    required this.index,
    required this.columnWidth,
    required this.scheduleColumnWidth,
    required this.statusColumnWidth,
    required this.borderColor,
    required this.textStyle,
    required this.tableCell,
  });

  final _Ticket ticket;
  final bool myRequests;
  final bool adminMode;
  final FetchTicketDevicesFn? fetchDevices;
  final VoidCallback onTicketCancelled;
  final int index;
  final double columnWidth;
  final double scheduleColumnWidth;
  final double statusColumnWidth;
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
  bool _showRepairHistory = false;
  String? _errorMessage;
  List<_TicketDevice> _devices = const [];
  List<String?> _technicians = const [];
  List<String?> _repairComments = const [];
  List<DateTime?> _repairTimes = const [];
  List<DateTime?> _repairEndTimes = const [];
  Map<int, List<_RepairHistoryPhoto>> _repairPhotos = const {};
  late final RealtimeRefreshBinding _realtimeRefresh;

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
      onRefresh: () async {
        if (_isExpanded) await _loadDevices();
      },
      isMounted: () => mounted,
    );
  }

  List<_RepairHistoryRow> get _repairHistory {
    final historyByIndex = <int, List<_RepairHistoryEntry>>{};
    for (final device in _devices) {
      for (final entry in device.repairHistory) {
        historyByIndex.putIfAbsent(entry.index, () => []).add(entry);
      }
    }

    final historyLength = historyByIndex.keys.fold<int>(
      [
        _repairTimes.length,
        _repairEndTimes.length,
        _technicians.length,
        _repairComments.length,
        _repairPhotos.keys.fold<int>(
          0,
          (length, index) => index + 1 > length ? index + 1 : length,
        ),
      ].reduce((first, second) => first > second ? first : second),
      (length, index) => index + 1 > length ? index + 1 : length,
    );
    final rows = List.generate(historyLength, (index) {
      final entries = historyByIndex[index] ?? const <_RepairHistoryEntry>[];
      final repairedDevices = entries
          .where((entry) => entry.progress == true)
          .map((entry) => entry.deviceName)
          .toSet()
          .join(', ');
      return _RepairHistoryRow(
        index: index,
        startTime: index < _repairTimes.length ? _repairTimes[index] : null,
        endTime: index < _repairEndTimes.length ? _repairEndTimes[index] : null,
        repairedDevices: repairedDevices,
        technician: index < _technicians.length ? _technicians[index] : null,
        comment:
            index < _repairComments.length &&
                _repairComments[index]?.trim().isNotEmpty == true
            ? _repairComments[index]
            : entries
                  .map((entry) => entry.comment)
                  .whereType<String>()
                  .firstWhere(
                    (comment) => comment.trim().isNotEmpty,
                    orElse: () => '',
                  ),
        photos: _repairPhotos[index] ?? const [],
      );
    });
    rows.sort((first, second) {
      final firstTime = first.startTime;
      final secondTime = second.startTime;
      if (firstTime == null && secondTime != null) return 1;
      if (firstTime != null && secondTime == null) return -1;
      if (firstTime == null || secondTime == null) return 0;
      final timeOrder = firstTime.compareTo(secondTime);
      return timeOrder != 0 ? timeOrder : first.index.compareTo(second.index);
    });
    return rows;
  }

  Future<void> _toggleExpanded() async {
    final willExpand = !_isExpanded;
    setState(() => _isExpanded = willExpand);
    if (!willExpand || _hasLoaded || _isLoading) return;

    await _loadDevices();
  }

  Future<void> _cancelRequest() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันยกเลิกคำร้อง'),
        content: Text(
          'ต้องการยกเลิกคำร้อง ${widget.ticket.ticketId} ใช่หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('กลับ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );
    if (shouldCancel != true || !mounted) return;

    final account = TemporaryAccountSession.instance.account;
    if (account == null || !SupabaseConnection.isInitialized) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเข้าสู่ระบบอีกครั้ง')));
      return;
    }

    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'list-public-tickets',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {'action': 'cancel-request', 'ticketId': widget.ticket.ticketId},
      );
      if (response.data is! Map || response.data['cancelled'] != true) {
        throw const FormatException('ไม่สามารถยืนยันการยกเลิกคำร้องได้');
      }
      if (mounted) widget.onTicketCancelled();
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ยกเลิกคำร้องไม่สำเร็จ: $error')));
    }
  }

  Future<void> _loadDevices() async {
    if (_isLoading) return;
    if (widget.fetchDevices != null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      try {
        final data = await widget.fetchDevices!(widget.ticket.ticketId);
        final rawDevices = data['devices'] as List? ?? [];
        final parsedDevices = rawDevices
            .whereType<Map>()
            .map((item) =>
                _TicketDevice.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        if (!mounted) return;
        setState(() {
          _devices = parsedDevices;
          _hasLoaded = true;
          _isLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
      return;
    }
    if (!SupabaseConnection.isInitialized) {
      setState(() => _errorMessage = 'ยังไม่ได้เชื่อมต่อ Supabase');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final account = TemporaryAccountSession.instance.account;
      final token = account?.accessToken ??
          SupabaseConnection.client.auth.currentSession?.accessToken;
      final response = await SupabaseConnection.client.functions.invoke(
        'list-public-tickets',
        headers: token != null && token.isNotEmpty
            ? {'Authorization': 'Bearer $token'}
            : null,
        body: {'action': 'devices', 'ticketId': widget.ticket.ticketId},
      );
      final data = response.data;
      if (data is! Map ||
          data['devices'] is! List ||
          (data['technician_history'] != null &&
              data['technician_history'] is! List) ||
          (data['fix_history_time_start'] != null &&
              data['fix_history_time_start'] is! List) ||
          (data['fix_history_time_end'] != null &&
              data['fix_history_time_end'] is! List) ||
          (data['technician_comment'] != null &&
              data['technician_comment'] is! List) ||
          (data['repair_history_photos'] != null &&
              data['repair_history_photos'] is! List)) {
        throw const FormatException('รูปแบบข้อมูลอุปกรณ์ไม่ถูกต้อง');
      }
      final devices = (data['devices'] as List)
          .map(_TicketDevice.fromJson)
          .toList(growable: false);
      final technicians = _stringList(
        data['technician_history'],
        'technician_history',
      );
      final repairComments = _stringList(
        data['technician_comment'],
        'technician_comment',
      );
      final repairTimes = _dateTimeList(
        data['fix_history_time_start'],
        'fix_history_time_start',
      );
      final repairEndTimes = _dateTimeList(
        data['fix_history_time_end'],
        'fix_history_time_end',
      );
      final repairPhotos = <int, List<_RepairHistoryPhoto>>{};
      for (final value in data['repair_history_photos'] as List? ?? const []) {
        if (value is! Map ||
            value['history_index'] is! int ||
            (value['deviceid'] != null && value['deviceid'] is! int) ||
            (value['row_index'] != null && value['row_index'] is! int) ||
            (value['photo_url'] != null && value['photo_url'] is! String)) {
          throw const FormatException('รูปแบบรูปประวัติการซ่อมไม่ถูกต้อง');
        }
        final photoUrl = value['photo_url'] as String?;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          repairPhotos
              .putIfAbsent(value['history_index'] as int, () => [])
              .add(
                _RepairHistoryPhoto(
                  deviceId: value['deviceid'] as int?,
                  rowIndex: value['row_index'] as int?,
                  photoUrl: photoUrl,
                ),
              );
        }
      }
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _technicians = technicians;
        _repairComments = repairComments;
        _repairTimes = repairTimes;
        _repairEndTimes = repairEndTimes;
        _repairPhotos = repairPhotos;
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

  Future<void> _editTicket() async {
    if (widget.ticket.status == 'cancel') return;
    if (!_hasLoaded) {
      await _loadDevices();
      if (!mounted || !_hasLoaded) return;
    }

    final changes = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) =>
          _AdminTicketEditDialog(ticket: widget.ticket, devices: _devices),
    );
    if (changes == null || !mounted) return;
    final account = TemporaryAccountSession.instance.account;
    if (account == null || !SupabaseConnection.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลระบบ')),
      );
      return;
    }

    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'list-public-tickets',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {
          'action': 'admin-update-ticket',
          'ticketId': widget.ticket.ticketId,
          ...changes,
        },
      );
      if (response.data is! Map || response.data['updated'] != true) {
        throw const FormatException('ไม่สามารถยืนยันการบันทึกข้อมูลได้');
      }
      if (!mounted) return;
      setState(() {
        _hasLoaded = false;
        _errorMessage = null;
      });
      widget.onTicketCancelled();
      await _loadDevices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกข้อมูลคำร้องเรียบร้อยแล้ว')),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ticketUpdateErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rowColor = widget.index.isEven
        ? colors.surface
        : colors.surfaceContainerLowest;
    final upcomingRepairPeriod = widget.ticket.upcomingRepairPeriod;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: InkWell(
            onTap: _toggleExpanded,
            child: Table(
              columnWidths: {
                for (var index = 0; index < 6; index++)
                  index: FixedColumnWidth(widget.columnWidth),
                6: FixedColumnWidth(widget.scheduleColumnWidth),
                7: FixedColumnWidth(widget.statusColumnWidth),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                verticalInside: BorderSide(
                  color: widget.borderColor,
                  width: 0.7,
                ),
                bottom: BorderSide(color: widget.borderColor, width: 0.7),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: rowColor),
                  children: [
                    widget.tableCell(
                      widget.ticket.ticketId,
                      backgroundColor: Colors.transparent,
                      textStyle: widget.textStyle?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    widget.tableCell(
                      _formatRequestDate(widget.ticket.requestDate),
                      backgroundColor: Colors.transparent,
                      textStyle: widget.textStyle,
                    ),
                    widget.tableCell(
                      widget.ticket.building,
                      backgroundColor: Colors.transparent,
                      textStyle: widget.textStyle,
                    ),
                    widget.tableCell(
                      widget.ticket.area ?? 'อาคาร ${widget.ticket.building}',
                      backgroundColor: Colors.transparent,
                      textStyle: widget.textStyle,
                    ),
                    widget.tableCell(
                      widget.ticket.floor ?? 'ไม่ระบุ',
                      backgroundColor: Colors.transparent,
                      textStyle: widget.textStyle,
                    ),
                    widget.tableCell(
                      widget.ticket.room ?? 'ไม่ระบุ',
                      backgroundColor: Colors.transparent,
                      textStyle: widget.textStyle,
                    ),
                    widget.tableCell(
                      upcomingRepairPeriod == null
                          ? 'ยังไม่มีกำหนด'
                          : _formatRepairDateRange(
                              upcomingRepairPeriod.start,
                              upcomingRepairPeriod.end,
                            ),
                      backgroundColor: Colors.transparent,
                      textStyle: widget.textStyle,
                    ),
                    widget.tableCell(
                      '',
                      backgroundColor: Colors.transparent,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _ticketStatusColor(
                                  widget.ticket.status,
                                ).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _ticketStatusLabel(widget.ticket.status),
                                style: TextStyle(
                                  color: _ticketStatusColor(widget.ticket.status),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (widget.myRequests &&
                                widget.ticket.status == 'validating')
                              IconButton(
                                tooltip: 'ยกเลิกคำร้อง',
                                onPressed: _cancelRequest,
                                icon: const Icon(Icons.close),
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 30,
                                  height: 30,
                                ),
                                color: colors.error,
                              ),
                            Icon(
                              _isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ..._buildExpandedTicketSlivers(context, rowColor),
      ],
    );
  }

  List<Widget> _buildExpandedTicketSlivers(
    BuildContext context,
    Color rowColor,
  ) {
    final colors = Theme.of(context).colorScheme;
    if (_isLoading) {
      return [
        SliverToBoxAdapter(child: _buildTicketDetailsHeading(context)),
        SliverToBoxAdapter(
          child: _buildDetailsMessage(
            const Center(child: CircularProgressIndicator()),
            colors,
          ),
        ),
      ];
    }
    if (_errorMessage case final error?) {
      return [
        SliverToBoxAdapter(child: _buildTicketDetailsHeading(context)),
        SliverToBoxAdapter(
          child: _buildDetailsMessage(
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [Text(error)],
            ),
            colors,
          ),
        ),
      ];
    }
    if (_showRepairHistory) {
      final history = _repairHistory;
      if (history.isEmpty) {
        return [
          SliverToBoxAdapter(child: _buildTicketDetailsHeading(context)),
          SliverToBoxAdapter(
            child: _buildDetailsMessage(
              const Text('ยังไม่มีข้อมูลประวัติการซ่อม'),
              colors,
            ),
          ),
        ];
      }
      return [
        SliverPersistentHeader(
          pinned: true,
          delegate: _TicketTableHeaderDelegate(
            child: _buildPinnedTicketDetailsHeader(
              context,
              _buildRepairHistoryHeader(context),
            ),
            height: 86,
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildRepairHistoryRow(context, history[index]),
            childCount: history.length,
          ),
        ),
      ];
    }
    if (_devices.isEmpty) {
      return [
        SliverToBoxAdapter(child: _buildTicketDetailsHeading(context)),
        SliverToBoxAdapter(
          child: _buildDetailsMessage(
            const Text('ไม่มีรายการอุปกรณ์ย่อย'),
            colors,
          ),
        ),
      ];
    }
    return [
      SliverPersistentHeader(
        pinned: true,
        delegate: _TicketTableHeaderDelegate(
          child: _buildPinnedTicketDetailsHeader(
            context,
            _buildDevicesHeader(context),
          ),
          height: 86,
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildDeviceRow(context, _devices[index]),
          childCount: _devices.length,
        ),
      ),
    ];
  }

  Widget _buildTicketDetailsHeading(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final totalWidth = (widget.columnWidth * 6) +
        widget.scheduleColumnWidth +
        widget.statusColumnWidth;

    return Container(
      width: totalWidth,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          Text(
            _showRepairHistory ? 'ประวัติการซ่อม' : 'อุปกรณ์ย่อย',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (widget.adminMode &&
              (widget.ticket.requesterDisplayName != null ||
                  widget.ticket.requesterUid != null)) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'ผู้ส่งคำร้อง ${widget.ticket.requesterDisplayName ?? '-'}(${widget.ticket.requesterUid ?? '-'})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          if (widget.adminMode) ...[
            IconButton(
              tooltip: widget.ticket.status == 'cancel'
                  ? 'คำร้องที่ยกเลิกแล้วไม่สามารถแก้ไขได้'
                  : 'แก้ไขข้อมูลคำร้อง',
              onPressed: _isLoading || widget.ticket.status == 'cancel'
                  ? null
                  : _editTicket,
              icon: const Icon(Icons.edit_outlined),
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints.tightFor(width: 40, height: 40),
            ),
            const SizedBox(width: 4),
          ],
          TextButton.icon(
            onPressed: () =>
                setState(() => _showRepairHistory = !_showRepairHistory),
            icon: Icon(
              _showRepairHistory
                  ? Icons.devices_other_outlined
                  : Icons.history,
            ),
            label:
                Text(_showRepairHistory ? 'อุปกรณ์ย่อย' : 'ประวัติการซ่อม'),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedTicketDetailsHeader(
    BuildContext context,
    Widget tableHeader,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTicketDetailsHeading(context),
        SizedBox(height: 44, child: tableHeader),
      ],
    );
  }

  Widget _buildDetailsMessage(Widget message, ColorScheme colors) {
    final totalWidth = (widget.columnWidth * 6) +
        widget.scheduleColumnWidth +
        widget.statusColumnWidth;
    return Container(
      width: totalWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: widget.borderColor)),
      ),
      child: message,
    );
  }

  Map<int, TableColumnWidth> _historyColumnWidths(double width) => {
    0: FixedColumnWidth(width * 0.20),
    1: FixedColumnWidth(width * 0.17),
    2: FixedColumnWidth(width * 0.23),
    3: FixedColumnWidth(width * 0.25),
    4: FixedColumnWidth(width * 0.15),
  };

  Widget _detailsTable({
    required Map<int, TableColumnWidth> columnWidths,
    required List<double> columnBreakpoints,
    required List<TableRow> rows,
  }) {
    return CustomPaint(
      foregroundPainter: _VerticalTableDividersPainter(
        columnBreakpoints: columnBreakpoints,
        color: widget.borderColor,
      ),
      child: Table(
        columnWidths: columnWidths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          bottom: BorderSide(color: widget.borderColor, width: 0.7),
        ),
        children: rows,
      ),
    );
  }

  Widget _buildRepairHistoryHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final headings = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final totalWidth = (widget.columnWidth * 6) +
        widget.scheduleColumnWidth +
        widget.statusColumnWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite &&
                constraints.maxWidth >= totalWidth
            ? constraints.maxWidth
            : totalWidth;
        return SizedBox(
          width: width,
          child: Container(
            color: colors.surfaceContainerLow,
            child: _detailsTable(
              columnWidths: _historyColumnWidths(width),
              columnBreakpoints: const [0.20, 0.37, 0.60, 0.85],
              rows: [
                TableRow(
                  children: [
                    for (final label in const [
                      'ช่วงเวลาที่ช่างทำงาน',
                      'ชื่อทีมช่าง',
                      'งานที่ซ่อมสำเร็จ',
                      'Comment ช่าง',
                      'รูปอุปกรณ์',
                    ])
                      _deviceCell(label, headings),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRepairHistoryRow(BuildContext context, _RepairHistoryRow entry) {
    final values = Theme.of(context).textTheme.bodyMedium;
    final colors = Theme.of(context).colorScheme;
    final totalWidth = (widget.columnWidth * 6) +
        widget.scheduleColumnWidth +
        widget.statusColumnWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite &&
                constraints.maxWidth >= totalWidth
            ? constraints.maxWidth
            : totalWidth;
        return SizedBox(
          width: width,
          child: Container(
            color: colors.surfaceContainerLow,
            child: _detailsTable(
              columnWidths: _historyColumnWidths(width),
              columnBreakpoints: const [0.20, 0.37, 0.60, 0.85],
              rows: [
                TableRow(
                  children: [
                    _deviceCell(
                      _formatRepairTimeRange(entry.startTime, entry.endTime),
                      values,
                    ),
                    _deviceCell(entry.technician ?? '-', values),
                    _deviceCell(
                      entry.repairedDevices.isEmpty
                          ? 'ไม่มีอุปกรณ์ที่ซ่อมสำเร็จ'
                          : entry.repairedDevices,
                      values,
                    ),
                    _deviceCell(
                      entry.comment?.trim().isNotEmpty == true
                          ? entry.comment!
                          : '-',
                      values,
                    ),
                    entry.photos.isNotEmpty
                        ? Wrap(
                            spacing: 4,
                            children: [
                              for (final photo in entry.photos)
                                TextButton.icon(
                                  onPressed: () => _viewRepairHistoryPhoto(
                                    context,
                                    photo.photoUrl,
                                  ),
                                  icon: const Icon(Icons.image_outlined),
                                  label: Text(
                                    photo.deviceId == null
                                        ? 'ดูรูป'
                                        : 'อุปกรณ์ ${photo.deviceId}',
                                  ),
                                ),
                            ],
                          )
                        : _deviceCell('-', values),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<int, TableColumnWidth> _deviceColumnWidths(double width) {
    return {
      0: FixedColumnWidth(width * 0.10),
      1: FixedColumnWidth(width * 0.20),
      2: FixedColumnWidth(width * 0.50),
      3: FixedColumnWidth(width * 0.20),
    };
  }

  Widget _buildDevicesHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final headings = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final totalWidth = (widget.columnWidth * 6) +
        widget.scheduleColumnWidth +
        widget.statusColumnWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite &&
                constraints.maxWidth >= totalWidth
            ? constraints.maxWidth
            : totalWidth;
        return SizedBox(
          width: width,
          child: Container(
            color: colors.surfaceContainerLow,
            child: _detailsTable(
              columnWidths: _deviceColumnWidths(width),
              columnBreakpoints: const [0.10, 0.30, 0.80],
              rows: [
                TableRow(
                  children: [
                    for (final label in const [
                      'ลำดับ',
                      'อุปกรณ์',
                      'รายละเอียด',
                      'สถานะ',
                    ])
                      _deviceCell(label, headings),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeviceRow(BuildContext context, _TicketDevice device) {
    final values = Theme.of(context).textTheme.bodyMedium;
    final colors = Theme.of(context).colorScheme;
    final totalWidth = (widget.columnWidth * 6) +
        widget.scheduleColumnWidth +
        widget.statusColumnWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite &&
                constraints.maxWidth >= totalWidth
            ? constraints.maxWidth
            : totalWidth;
        return SizedBox(
          width: width,
          child: Container(
            color: colors.surfaceContainerLow,
            child: _detailsTable(
              columnWidths: _deviceColumnWidths(width),
              columnBreakpoints: const [0.10, 0.30, 0.80],
              rows: [
                TableRow(
                  children: [
                    _deviceCell(device.deviceId.toString(), values),
                    _deviceCell(device.name, values),
                    _deviceCell(device.description ?? '-', values),
                    _deviceCell(
                      _ticketStatusLabel(device.status),
                      values?.copyWith(
                        color: _ticketStatusColor(device.status),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatRepairTimeRange(DateTime? start, DateTime? end) {
    if (start == null) return end == null ? '-' : _formatDate(end);
    if (end == null || _isSameLocalDay(start, end)) {
      return _formatDate(start);
    }
    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatRepairDateRange(DateTime? start, DateTime? end) {
    if (start == null) return end == null ? '-' : _formatDate(end);
    if (end == null) return _formatDate(start);
    return '${_formatDate(start)}\n-\n${_formatDate(end)}';
  }

  bool _isSameLocalDay(DateTime first, DateTime second) {
    final firstLocal = first.toLocal();
    final secondLocal = second.toLocal();
    return firstLocal.year == secondLocal.year &&
        firstLocal.month == secondLocal.month &&
        firstLocal.day == secondLocal.day;
  }

  String _formatDate(DateTime dateTime) {
    final localDateTime = dateTime.toLocal();
    final day = localDateTime.day.toString().padLeft(2, '0');
    final month = localDateTime.month.toString().padLeft(2, '0');
    return '$day/$month/${localDateTime.year}';
  }


  Widget _deviceCell(String text, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        text,
        style: style,
        softWrap: true,
        overflow: TextOverflow.clip,
      ),
    );
  }

  @override
  void dispose() {
    _realtimeRefresh.dispose();
    super.dispose();
  }
}

class _AdminTicketEditDialog extends StatefulWidget {
  const _AdminTicketEditDialog({required this.ticket, required this.devices});

  final _Ticket ticket;
  final List<_TicketDevice> devices;

  @override
  State<_AdminTicketEditDialog> createState() => _AdminTicketEditDialogState();
}

class _AdminTicketEditDialogState extends State<_AdminTicketEditDialog> {
  static const _statuses = ['pending', 'finish', 'rejected'];
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _areaController;
  late final TextEditingController _floorController;
  late final TextEditingController _roomController;
  late final List<_DeviceEditControllers> _deviceControllers;
  late String _status;
  late String? _selectedBuilding;
  late double _latitude;
  late double _longitude;
  bool _otherCoordinatesSelected = false;
  _MaintenanceTeam? _selectedTeam;
  TextEditingController? _teamSearchController;
  List<_MaintenanceTeam> _eligibleTeams = const [];
  bool _isLoadingTeams = true;
  int _teamLoadVersion = 0;
  String? _teamLoadError;
  late final RealtimeRefreshBinding _realtimeRefresh;

  bool get _canSelectTechnicianTeam => _status == 'pending';
  bool get _requiresTechnicianTeam =>
      _canSelectTechnicianTeam && _selectedTeam == null;
  bool get _requiresPendingDevice =>
      _status == 'pending' &&
      !_deviceControllers.any((device) => device.status == 'pending');

  bool get _hasValidatingStatus =>
      _status == 'validating' ||
      _deviceControllers.any((device) => device.status == 'validating');

  @override
  void initState() {
    super.initState();
    _realtimeRefresh = RealtimeRefreshBinding(
      domains: const {RealtimeInvalidationDomain.technicians},
      onRefresh: () async {
        if (_canSelectTechnicianTeam) await _loadEligibleTeams();
      },
      isMounted: () => mounted,
    );
    final ticket = widget.ticket;
    _selectedBuilding = ticket.building == 'other'
        ? otherBuildingLabel
        : buildingOptions.cast<String?>().firstWhere(
            (option) =>
                option != null &&
                RegExp(r'\d+').firstMatch(option)?.group(0) == ticket.building,
            orElse: () => null,
          );
    _latitude = ticket.latitude;
    _longitude = ticket.longitude;
    if (_selectedBuilding == otherBuildingLabel) {
      _otherCoordinatesSelected = true;
    } else if (_selectedBuilding != null) {
      final buildingNumber = RegExp(
        r'\d+',
      ).firstMatch(_selectedBuilding!)!.group(0)!;
      final coordinates = buildingCoordinates[buildingNumber];
      if (coordinates != null) {
        _latitude = coordinates.$1;
        _longitude = coordinates.$2;
      }
    }
    _areaController = TextEditingController(text: ticket.area ?? '');
    _floorController = TextEditingController(text: ticket.floor ?? '');
    _roomController = TextEditingController(text: ticket.room ?? '');
    _status = _statuses.contains(ticket.status) ? ticket.status : 'validating';
    if (_selectedBuilding != null && _selectedBuilding != otherBuildingLabel) {
      _areaController.text = 'อาคาร ${ticket.building}';
    }
    _deviceControllers = widget.devices
        .map(_DeviceEditControllers.fromDevice)
        .toList(growable: false);
    unawaited(_loadEligibleTeams());
  }

  @override
  void dispose() {
    _realtimeRefresh.dispose();
    _areaController.dispose();
    _floorController.dispose();
    _roomController.dispose();
    _teamSearchController = null;
    for (final device in _deviceControllers) {
      device.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEligibleTeams() async {
    final loadVersion = ++_teamLoadVersion;
    setState(() {
      _isLoadingTeams = true;
      _teamLoadError = null;
    });
    final account = TemporaryAccountSession.instance.account;
    if (account == null) {
      setState(() {
        _isLoadingTeams = false;
        _teamLoadError = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลระบบ';
      });
      return;
    }
    if (!SupabaseConnection.isInitialized) {
      setState(() {
        _isLoadingTeams = false;
        _teamLoadError = 'ยังไม่ได้เชื่อมต่อ Supabase';
      });
      return;
    }

    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'maintenance-teams',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {'action': 'list-eligible-teams'},
      );
      final data = response.data;
      if (data is! Map || data['teams'] is! List) {
        throw const FormatException('รูปแบบรายชื่อทีมช่างไม่ถูกต้อง');
      }
      final teams = (data['teams'] as List)
          .map(_MaintenanceTeam.fromJson)
          .toList(growable: false);
      if (!mounted || loadVersion != _teamLoadVersion) return;
      setState(() {
        _eligibleTeams = teams;
        _selectedTeam = teams
            .where((team) => team.name == widget.ticket.technicianTeam)
            .firstOrNull;
        if (!_canSelectTechnicianTeam) _selectedTeam = null;
        _isLoadingTeams = false;
        _teamLoadError = null;
      });
    } on Exception catch (error) {
      if (!mounted || loadVersion != _teamLoadVersion) return;
      setState(() {
        _isLoadingTeams = false;
        _teamLoadError = 'โหลดทีมช่างไม่สำเร็จ: $error';
      });
    }
  }

  Future<void> _chooseOtherBuildingCoordinates() async {
    final initialPosition = latlong.LatLng(_latitude, _longitude);
    var selectedPosition = initialPosition;
    final result = await showDialog<latlong.LatLng>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('เลือกตำแหน่งบนแผนที่'),
          content: SizedBox(
            width: 600,
            height: 420,
            child: Column(
              children: [
                Expanded(
                  child: flutter_map.FlutterMap(
                    options: flutter_map.MapOptions(
                      initialCenter: selectedPosition,
                      initialZoom: 16,
                      onTap: (_, position) =>
                          setDialogState(() => selectedPosition = position),
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
                            point: selectedPosition,
                            child: Icon(
                              Icons.location_pin,
                              color: Theme.of(context).colorScheme.error,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                      const flutter_map.RichAttributionWidget(
                        showFlutterMapAttribution: false,
                        attributions: [
                          flutter_map.TextSourceAttribution(
                            '© OpenStreetMap contributors',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Latitude: ${selectedPosition.latitude.toStringAsFixed(6)}  '
                  'Longitude: ${selectedPosition.longitude.toStringAsFixed(6)}',
                  textAlign: TextAlign.center,
                ),
                const Text('แตะบนแผนที่เพื่อเลือกตำแหน่ง'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedPosition),
              child: const Text('เลือกตำแหน่งนี้'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _latitude = result.latitude;
      _longitude = result.longitude;
      _otherCoordinatesSelected = true;
    });
  }

  void _save() {
    if (_hasValidatingStatus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'กรุณาเปลี่ยนสถานะคำร้องและอุปกรณ์ที่ยังเป็น “รอการยืนยัน”',
          ),
        ),
      );
      return;
    }
    if (_requiresTechnicianTeam) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกทีมช่างก่อนบันทึก')),
      );
      return;
    }
    if (_canSelectTechnicianTeam && _selectedTeam != null) {
      final period = _selectedTeam!.nextRepairPeriod;
      final today = DateTime.now();
      final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);

      if (period.end.isBefore(todayEnd.subtract(const Duration(days: 1)))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ทีมช่างที่เลือกไม่มีช่วงเวลาปฏิบัติงานที่ใช้งานได้ในปัจจุบัน กรุณาเพิ่มเวลาทำงานให้ทีมช่างในหน้าจัดการช่างก่อน',
            ),
          ),
        );
        return;
      }
    }
    if (_requiresPendingDevice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'สถานะคำร้อง “รอซ่อม” ต้องมีอุปกรณ์สถานะ “รอซ่อม” อย่างน้อย 1 รายการ',
          ),
        ),
      );
      return;
    }
    if (_selectedBuilding == otherBuildingLabel && !_otherCoordinatesSelected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเลือกพิกัดบนแผนที่')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final devices = <Map<String, Object?>>[];
    final selectedRepairPeriod = _canSelectTechnicianTeam
        ? _selectedTeam?.nextRepairPeriod
        : null;
    for (var index = 0; index < widget.devices.length; index++) {
      final device = widget.devices[index];
      final fields = _deviceControllers[index];
      devices.add({
        'deviceid': device.deviceId,
        'device': fields.name.text.trim(),
        'discription': fields.description.text.trim(),
        'status': fields.status,
        'next_fix_date': fields.status == 'pending'
            ? (selectedRepairPeriod != null
                ? bangkokDateBoundaryIso8601(selectedRepairPeriod.end)
                : device.nextFixDate?.toIso8601String())
            : null,
        'technician_comment': fields.technicianComments.text
            .split('\n')
            .map((comment) => comment.trim())
            .where((comment) => comment.isNotEmpty)
            .toList(),
      });
    }
    Navigator.of(context).pop({
      'request': {
        'building': _selectedBuilding == otherBuildingLabel
            ? 'other'
            : RegExp(r'\d+').firstMatch(_selectedBuilding!)!.group(0),
        'latitude': _latitude,
        'longtitude': _longitude,
        'area': _selectedBuilding == otherBuildingLabel
            ? _areaController.text.trim()
            : null,
        'floor': _floorController.text.trim().isEmpty
            ? null
            : _floorController.text.trim(),
        'room': _roomController.text.trim().isEmpty
            ? null
            : _roomController.text.trim(),
        'status': _status,
        'technician_team': _canSelectTechnicianTeam
            ? _selectedTeam?.name
            : null,
        'next_fix_date_start': selectedRepairPeriod == null
            ? null
            : bangkokDateBoundaryIso8601(selectedRepairPeriod.start),
        'next_fix_date_end': selectedRepairPeriod == null
            ? null
            : bangkokDateBoundaryIso8601(selectedRepairPeriod.end),
      },
      'devices': devices,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('แก้ไขคำร้อง ${widget.ticket.ticketId}'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ข้อมูลคำร้อง',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _selectedBuilding ?? ''),
                  optionsBuilder: (textEditingValue) {
                    final query = textEditingValue.text.trim().toLowerCase();
                    return buildingOptions.where(
                      (building) =>
                          query.isEmpty ||
                          building.toLowerCase().contains(query),
                    );
                  },
                  onSelected: (building) {
                    setState(() {
                      _selectedBuilding = building;
                      if (building == otherBuildingLabel) {
                        _otherCoordinatesSelected =
                            widget.ticket.building == 'other' &&
                            _selectedBuilding == otherBuildingLabel;
                        if (widget.ticket.building != 'other') {
                          _areaController.clear();
                        }
                      } else {
                        final buildingNumber = RegExp(
                          r'\d+',
                        ).firstMatch(building)!.group(0)!;
                        _areaController.text = 'อาคาร $buildingNumber';
                        final coordinates = buildingCoordinates[buildingNumber];
                        if (coordinates != null) {
                          _latitude = coordinates.$1;
                          _longitude = coordinates.$2;
                        }
                        _otherCoordinatesSelected = false;
                      }
                    });
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) =>
                          TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'อาคาร',
                              hintText: 'พิมพ์เพื่อค้นหาอาคาร',
                            ),
                            onChanged: (value) {
                              if (value != _selectedBuilding) {
                                setState(() => _selectedBuilding = null);
                              }
                            },
                            validator: (value) => _selectedBuilding == null
                                ? 'กรุณาเลือกอาคารจากรายการ'
                                : null,
                          ),
                  optionsViewBuilder: (context, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: SizedBox(
                        width: 500,
                        height: 240,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final building = options.elementAt(index);
                            return ListTile(
                              title: Text(building),
                              onTap: () => onSelected(building),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (_selectedBuilding == otherBuildingLabel) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _chooseOtherBuildingCoordinates,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('เลือก Latitude / Longitude บนแผนที่'),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Latitude: ${_latitude.toStringAsFixed(6)}  '
                    'Longitude: ${_longitude.toStringAsFixed(6)}',
                    textAlign: TextAlign.center,
                  ),
                ),
                TextFormField(
                  controller: _areaController,
                  readOnly: _selectedBuilding != otherBuildingLabel,
                  decoration: InputDecoration(
                    labelText: 'บริเวณ',
                    helperText: _selectedBuilding != otherBuildingLabel
                        ? 'ระบบใส่ชื่ออาคารและเลขอาคารให้อัตโนมัติ'
                        : 'ระบุบริเวณได้อิสระ',
                  ),
                  validator: (value) =>
                      _selectedBuilding == otherBuildingLabel &&
                          (value == null || value.trim().isEmpty)
                      ? 'กรุณาระบุบริเวณ'
                      : null,
                ),
                TextFormField(
                  controller: _floorController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final value = int.tryParse(newValue.text);
                      if (value != null && value <= 50) {
                        return newValue;
                      }
                      return oldValue;
                    }),
                  ],
                  decoration: InputDecoration(
                    labelText: _selectedBuilding == otherBuildingLabel
                        ? 'ชั้น'
                        : 'ชั้น *',
                  ),
                  validator: (value) {
                    final floor = value?.trim() ?? '';
                    if (_selectedBuilding != null &&
                        _selectedBuilding != otherBuildingLabel &&
                        floor.isEmpty) {
                      return 'กรุณาระบุชั้น';
                    }
                    if (floor.isNotEmpty) {
                      final floorNumber = int.tryParse(floor);
                      if (floorNumber == null ||
                          floorNumber < 1 ||
                          floorNumber > 50) {
                        return 'กรุณาระบุชั้นเป็นตัวเลขระหว่าง 1 ถึง 50';
                      }
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _roomController,
                  decoration: const InputDecoration(labelText: 'ห้อง'),
                  validator: (value) {
                    final room = value?.trim() ?? '';
                    if (room.isNotEmpty &&
                        !RegExp(r'^[a-zA-Z0-9-]{1,8}$').hasMatch(room)) {
                      return 'ห้องกรอกได้ไม่เกิน 8 ตัวอักษร';
                    }
                    return null;
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _statuses.contains(_status) ? _status : null,
                  decoration: const InputDecoration(labelText: 'สถานะคำร้อง'),
                  items: [
                    for (final status in _statuses)
                      DropdownMenuItem(
                        value: status,
                        child: Text(
                          _ticketStatusLabel(status),
                          style: TextStyle(color: _ticketStatusColor(status)),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _status = value;
                      if (value == 'rejected') {
                        for (final device in _deviceControllers) {
                          device.status = 'rejected';
                        }
                      } else if (value == 'finish') {
                        for (final device in _deviceControllers) {
                          if (!{'rejected', 'finish'}.contains(device.status)) {
                            device.status = 'finish';
                          }
                        }
                      }
                      if (!_canSelectTechnicianTeam) {
                        _selectedTeam = null;
                        _teamSearchController?.clear();
                      }
                    });
                  },
                  validator: (value) =>
                      value == null ? 'กรุณาเลือกสถานะคำร้อง' : null,
                ),
                Autocomplete<_MaintenanceTeam>(
                  key: ValueKey(_isLoadingTeams),
                  initialValue: TextEditingValue(
                    text: !_canSelectTechnicianTeam
                        ? ''
                        : _selectedTeam?.name ?? '',
                  ),
                  displayStringForOption: (team) => team.name,
                  optionsBuilder: (textEditingValue) {
                    if (!_canSelectTechnicianTeam ||
                        _isLoadingTeams ||
                        _teamLoadError != null) {
                      return const [];
                    }
                    final query = textEditingValue.text.trim().toLowerCase();
                    return _eligibleTeams.where(
                      (team) =>
                          query.isEmpty ||
                          team.name.toLowerCase().contains(query),
                    );
                  },
                  onSelected: (team) => setState(() => _selectedTeam = team),
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                        _teamSearchController = controller;
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled:
                              _canSelectTechnicianTeam &&
                              !_isLoadingTeams &&
                              _teamLoadError == null,
                          decoration: InputDecoration(
                            labelText: 'ทีมช่าง',
                            hintText: !_canSelectTechnicianTeam
                                ? 'สถานะนี้ไม่สามารถเลือกทีมช่างได้'
                                : 'พิมพ์เพื่อค้นหาทีมช่าง',
                            helperText: _canSelectTechnicianTeam
                                ? 'วันซ่อมถัดไปกำหนดจากวันที่ทีมช่างเข้าใช้งานได้ใกล้ที่สุด'
                                : null,
                            suffixIcon: _isLoadingTeams
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          onChanged: (value) {
                            if (_selectedTeam?.name != value) {
                              setState(() => _selectedTeam = null);
                            }
                          },
                        );
                      },
                  optionsViewBuilder: (context, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: SizedBox(
                        width: 500,
                        height: 300,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final team = options.elementAt(index);
                            final today = DateTime.now();
                            final isExpired = team.nextRepairPeriod.end.isBefore(
                              DateTime(today.year, today.month, today.day),
                            );
                            return ListTile(
                              title: Row(
                                children: [
                                  Text(team.name),
                                  if (isExpired) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'หมดเวลาปฏิบัติงาน',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade800,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(team.periodSummary),
                              onTap: () => onSelected(team),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (_teamLoadError case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [Expanded(child: Text(error))]),
                  ),
                if (_requiresTechnicianTeam && _teamLoadError == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'กรุณาเลือกทีมช่างก่อนบันทึกคำร้องสถานะ “รอซ่อม”',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                const Divider(height: 32),
                Text(
                  'ข้อมูลดำเนินงานและอุปกรณ์',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (var index = 0; index < widget.devices.length; index++)
                  _buildDeviceFields(index),
                if (_requiresPendingDevice)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'สถานะคำร้อง “รอซ่อม” ต้องมีอุปกรณ์สถานะ “รอซ่อม” อย่างน้อย 1 รายการ',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton.icon(
          onPressed:
              _hasValidatingStatus ||
                  _requiresTechnicianTeam ||
                  _requiresPendingDevice
              ? null
              : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('บันทึก'),
        ),
      ],
    );
  }

  Widget _buildDeviceFields(int index) {
    final device = widget.devices[index];
    final fields = _deviceControllers[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'อุปกรณ์ ${device.deviceId}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (device.photoUrl case final photoUrl?)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _viewDevicePhoto(device, photoUrl),
              icon: const Icon(Icons.image_outlined),
              label: const Text('ดูรูปอุปกรณ์'),
            ),
          )
        else
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('ไม่มีรูปอุปกรณ์'),
          ),
        TextFormField(
          controller: fields.name,
          decoration: const InputDecoration(labelText: 'ชื่ออุปกรณ์'),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'กรุณาระบุชื่ออุปกรณ์'
              : null,
        ),
        TextFormField(
          controller: fields.description,
          decoration: const InputDecoration(labelText: 'รายละเอียดอุปกรณ์'),
          maxLines: 2,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('${device.deviceId}-${fields.status}'),
          initialValue: _allowedDeviceStatuses.contains(fields.status)
              ? fields.status
              : null,
          decoration: const InputDecoration(labelText: 'สถานะอุปกรณ์'),
          items: [
            for (final status in _allowedDeviceStatuses)
              DropdownMenuItem(
                value: status,
                child: Text(
                  _ticketStatusLabel(status),
                  style: TextStyle(color: _ticketStatusColor(status)),
                ),
              ),
          ],
          onChanged: _status == 'rejected'
              ? null
              : (value) {
                  if (value != null) setState(() => fields.status = value);
                },
          validator: (value) => value == null ? 'กรุณาเลือกสถานะอุปกรณ์' : null,
        ),
      ],
    );
  }

  List<String> get _allowedDeviceStatuses => switch (_status) {
    'rejected' => const ['rejected'],
    'finish' => const ['rejected', 'finish'],
    _ => _deviceStatuses,
  };

  Future<void> _viewDevicePhoto(_TicketDevice device, String photoUrl) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('รูปอุปกรณ์ ${device.deviceId}'),
        content: SizedBox(
          width: 640,
          height: 480,
          child: InteractiveViewer(
            child: Image.network(
              photoUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text('โหลดรูปอุปกรณ์ไม่สำเร็จ กรุณาปิดแล้วลองใหม่'),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}

Future<void> _viewRepairHistoryPhoto(BuildContext context, String photoUrl) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('รูปอุปกรณ์ที่ซ่อม'),
      content: SizedBox(
        width: 640,
        height: 480,
        child: InteractiveViewer(
          child: Image.network(
            photoUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Text('โหลดรูปไม่สำเร็จ กรุณาปิดแล้วลองใหม่'),
            ),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}

class _DeviceEditControllers {
  _DeviceEditControllers({
    required this.name,
    required this.description,
    required this.status,
    required this.technicianComments,
  });

  final TextEditingController name;
  final TextEditingController description;
  String status;
  final TextEditingController technicianComments;

  factory _DeviceEditControllers.fromDevice(_TicketDevice device) {
    return _DeviceEditControllers(
      name: TextEditingController(text: device.name),
      description: TextEditingController(text: device.description ?? ''),
      status: _deviceStatuses.contains(device.status)
          ? device.status
          : 'validating',
      technicianComments: TextEditingController(
        text: device.technicianComments.whereType<String>().join('\n'),
      ),
    );
  }

  void dispose() {
    name.dispose();
    description.dispose();
    technicianComments.dispose();
  }
}

const _deviceStatuses = ['pending', 'rejected', 'finish'];

String _ticketStatusLabel(String status) => switch (status) {
  'validating' => 'รอการยืนยัน',
  'pending' => 'รอซ่อม',
  'rejected' => 'ปฏิเสธการซ่อม',
  'cancel' => 'ยกเลิก',
  'finish' => 'ซ่อมเสร็จสิ้น',
  _ => status,
};

Color _ticketStatusColor(String status) => switch (status) {
  'validating' => Colors.blue.shade700,
  'pending' => Colors.amber.shade800,
  'rejected' => Colors.red.shade700,
  'cancel' => Colors.deepOrange.shade700,
  'finish' => Colors.green.shade700,
  _ => Colors.grey.shade700,
};

class _MaintenanceTeam {
  const _MaintenanceTeam({required this.name, required this.periods});

  final String name;
  final List<_MaintenanceAccessPeriod> periods;

  String get periodSummary {
    final period = nextRepairPeriod;
    return '${DateFormat('dd/MM/yyyy').format(period.start)} - '
        '${DateFormat('dd/MM/yyyy').format(period.end)} '
        '(${period.remainingText})';
  }

  _MaintenanceAccessPeriod get nextRepairPeriod {
    final period = periods.first;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return _MaintenanceAccessPeriod(
      start: period.start.isBefore(todayStart) ? todayStart : period.start,
      end: period.end,
    );
  }

  factory _MaintenanceTeam.fromJson(dynamic value) {
    if (value is! Map ||
        value['name'] is! String ||
        value['periods'] is! List) {
      throw const FormatException('ข้อมูลทีมช่างไม่ถูกต้อง');
    }
    final periods = (value['periods'] as List)
        .map(_MaintenanceAccessPeriod.fromJson)
        .toList(growable: false);
    if (periods.isEmpty) {
      throw const FormatException('ทีมช่างไม่มีช่วงเวลาเข้าใช้งาน');
    }
    return _MaintenanceTeam(name: value['name'] as String, periods: periods);
  }
}

class _MaintenanceAccessPeriod {
  const _MaintenanceAccessPeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  String get remainingText {
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    final remaining = endExclusive.difference(DateTime.now());
    if (remaining <= Duration.zero) return 'หมดเวลาแล้ว';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    if (days == 0) return 'เหลือ ${remaining.inHours} ชม.';
    return hours == 0 ? 'เหลือ $days วัน' : 'เหลือ $days วัน $hours ชม.';
  }

  factory _MaintenanceAccessPeriod.fromJson(dynamic value) {
    if (value is! Map || value['start'] is! String || value['end'] is! String) {
      throw const FormatException('ช่วงเวลาเข้าใช้งานทีมช่างไม่ถูกต้อง');
    }
    final start = DateTime.tryParse(value['start'] as String);
    final end = DateTime.tryParse(value['end'] as String);
    if (start == null || end == null || start.isAfter(end)) {
      throw const FormatException('ช่วงเวลาเข้าใช้งานทีมช่างไม่ถูกต้อง');
    }
    return _MaintenanceAccessPeriod(start: start.toLocal(), end: end.toLocal());
  }
}

class _Ticket {
  const _Ticket({
    required this.ticketId,
    required this.requestDate,
    required this.building,
    required this.latitude,
    required this.longitude,
    required this.area,
    required this.floor,
    required this.room,
    required this.nextFixDateStart,
    required this.nextFixDateEnd,
    required this.status,
    required this.technicianTeam,
    this.requesterUid,
    this.requesterDisplayName,
  });

  final String ticketId;
  final DateTime requestDate;
  final String building;
  final double latitude;
  final double longitude;
  final String? area;
  final String? floor;
  final String? room;
  final DateTime? nextFixDateStart;
  final DateTime? nextFixDateEnd;
  final String status;
  final String? technicianTeam;
  final String? requesterUid;
  final String? requesterDisplayName;

  _RepairTimeRange? get upcomingRepairPeriod {
    final start = nextFixDateStart;
    final end = nextFixDateEnd;
    if (start == null || end == null) return null;
    return _RepairTimeRange(start: start, end: end);
  }

  factory _Ticket.fromJson(dynamic value) {
    if (value is! Map ||
        value['TicketId'] is! String ||
        value['request_date'] is! String ||
        value['building'] is! String ||
        (value['latitude'] != null && value['latitude'] is! num) ||
        (value['longtitude'] != null && value['longtitude'] is! num) ||
        value['status'] is! String ||
        (value['area'] != null && value['area'] is! String) ||
        (value['floor'] != null && value['floor'] is! String) ||
        (value['room'] != null && value['room'] is! String) ||
        (value['technician_team'] != null &&
            value['technician_team'] is! String) ||
        (value['requester_uid'] != null && value['requester_uid'] is! String) ||
        (value['requester_display_name'] != null &&
            value['requester_display_name'] is! String) ||
        (value['next_fix_date_start'] != null &&
            value['next_fix_date_start'] is! String) ||
        (value['next_fix_date_end'] != null &&
            value['next_fix_date_end'] is! String)) {
      throw const FormatException('ข้อมูล Ticket ไม่ครบถ้วน');
    }
    final nextFixDateStartValue = value['next_fix_date_start'] as String?;
    final nextFixDateEndValue = value['next_fix_date_end'] as String?;
    final nextFixDateStart = nextFixDateStartValue == null
        ? null
        : DateTime.tryParse(nextFixDateStartValue);
    final nextFixDateEnd = nextFixDateEndValue == null
        ? null
        : DateTime.tryParse(nextFixDateEndValue);
    if ((nextFixDateStartValue != null && nextFixDateStart == null) ||
        (nextFixDateEndValue != null && nextFixDateEnd == null) ||
        (nextFixDateStart == null) != (nextFixDateEnd == null) ||
        (nextFixDateStart != null &&
            nextFixDateEnd != null &&
            nextFixDateStart.isAfter(nextFixDateEnd))) {
      throw const FormatException('รูปแบบช่วงวันเข้าซ่อมไม่ถูกต้อง');
    }
    final requestDateValue = value['request_date'] as String;
    final requestDate = DateTime.tryParse(requestDateValue);
    if (requestDate == null) {
      throw const FormatException('รูปแบบวันที่แจ้งไม่ถูกต้อง');
    }
    final building = value['building'] as String;
    final buildingNumber = RegExp(r'\d+').firstMatch(building)?.group(0);
    final defaultCoordinates = buildingCoordinates[buildingNumber];
    final latitude = value['latitude'] is num
        ? (value['latitude'] as num).toDouble()
        : defaultCoordinates?.$1 ?? _ticketLocationMapCenter.latitude;
    final longitude = value['longtitude'] is num
        ? (value['longtitude'] as num).toDouble()
        : defaultCoordinates?.$2 ?? _ticketLocationMapCenter.longitude;
    return _Ticket(
      ticketId: value['TicketId'] as String,
      requestDate: requestDate,
      building: building,
      latitude: latitude,
      longitude: longitude,
      area: value['area'] as String?,
      floor: value['floor'] as String?,
      room: value['room'] as String?,
      nextFixDateStart: nextFixDateStart,
      nextFixDateEnd: nextFixDateEnd,
      status: value['status'] as String,
      technicianTeam: value['technician_team'] as String?,
      requesterUid: value['requester_uid'] as String?,
      requesterDisplayName: value['requester_display_name'] as String?,
    );
  }
}

class _RepairTimeRange {
  const _RepairTimeRange({required this.start, required this.end});

  final DateTime? start;
  final DateTime? end;
}

class _TicketDevice {
  const _TicketDevice({
    required this.deviceId,
    required this.name,
    required this.description,
    required this.status,
    required this.photoUrl,
    required this.nextFixDate,
    required this.technicianComments,
    required this.repairHistory,
  });

  final int deviceId;
  final String name;
  final String? description;
  final String status;
  final String? photoUrl;
  final DateTime? nextFixDate;
  final List<String?> technicianComments;
  final List<_RepairHistoryEntry> repairHistory;

  factory _TicketDevice.fromJson(dynamic value) {
    if (value is! Map ||
        value['deviceid'] is! int ||
        value['device'] is! String ||
        value['status'] is! String ||
        (value['photo_url'] != null && value['photo_url'] is! String) ||
        (value['discription'] != null && value['discription'] is! String)) {
      throw const FormatException('ข้อมูลอุปกรณ์ไม่ครบถ้วน');
    }
    final nextFixDate = _lastDateTime(value['next_fix_date'], 'next_fix_date');
    final technicianComments = _stringList(
      value['technician_comment'],
      'technician_comment',
    );
    final progress = _boolList(
      value['fix_history_progress'],
      'fix_history_progress',
    );
    final historyLength = progress.length;
    final repairHistory = List.generate(
      historyLength,
      (index) => _RepairHistoryEntry(
        deviceName: value['device'] as String,
        index: index,
        progress: index < progress.length ? progress[index] : null,
        comment: index < technicianComments.length
            ? technicianComments[index]
            : null,
      ),
      growable: false,
    );
    return _TicketDevice(
      deviceId: value['deviceid'] as int,
      name: value['device'] as String,
      description: value['discription'] as String?,
      status: value['status'] as String,
      photoUrl: value['photo_url'] as String?,
      nextFixDate: nextFixDate,
      technicianComments: technicianComments,
      repairHistory: repairHistory,
    );
  }
}

class _RepairHistoryEntry {
  const _RepairHistoryEntry({
    required this.deviceName,
    required this.index,
    required this.progress,
    required this.comment,
  });

  final String deviceName;
  final int index;
  final bool? progress;
  final String? comment;
}

class _RepairHistoryRow {
  const _RepairHistoryRow({
    required this.index,
    required this.startTime,
    required this.endTime,
    required this.repairedDevices,
    required this.technician,
    required this.comment,
    required this.photos,
  });

  final int index;
  final DateTime? startTime;
  final DateTime? endTime;
  final String repairedDevices;
  final String? technician;
  final String? comment;
  final List<_RepairHistoryPhoto> photos;
}

class _RepairHistoryPhoto {
  const _RepairHistoryPhoto({
    required this.deviceId,
    required this.rowIndex,
    required this.photoUrl,
  });

  final int? deviceId;
  final int? rowIndex;
  final String photoUrl;
}

class _TicketTableHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TicketTableHeaderDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);

  @override
  bool shouldRebuild(covariant _TicketTableHeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
}

class _VerticalTableDividersPainter extends CustomPainter {
  const _VerticalTableDividersPainter({
    required this.columnBreakpoints,
    required this.color,
  });

  final List<double> columnBreakpoints;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.square;
    for (final breakpoint in columnBreakpoints) {
      final x = size.width * breakpoint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalTableDividersPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.columnBreakpoints != columnBreakpoints;
}

String _formatRequestDate(DateTime dateTime) {
  final localDateTime = dateTime.toLocal();
  final day = localDateTime.day.toString().padLeft(2, '0');
  final month = localDateTime.month.toString().padLeft(2, '0');
  return '$day/$month/${localDateTime.year}';
}

DateTime? _lastDateTime(Object? value, String fieldName) {
  if (value == null) return null;
  final values = value is List ? value.reversed : [value];
  for (final item in values) {
    if (item == null) continue;
    if (item is! String) {
      throw FormatException('รูปแบบข้อมูล $fieldName ไม่ถูกต้อง');
    }
    final dateTime = DateTime.tryParse(item);
    if (dateTime == null) {
      throw FormatException('รูปแบบวันเวลาใน $fieldName ไม่ถูกต้อง');
    }
    return dateTime;
  }
  return null;
}

List<DateTime?> _dateTimeList(Object? value, String fieldName) {
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('รูปแบบข้อมูล $fieldName ไม่ถูกต้อง');
  }
  return value
      .map((item) {
        if (item == null) return null;
        if (item is! String) {
          throw FormatException('รูปแบบข้อมูล $fieldName ไม่ถูกต้อง');
        }
        final dateTime = DateTime.tryParse(item);
        if (dateTime == null) {
          throw FormatException('รูปแบบวันเวลาใน $fieldName ไม่ถูกต้อง');
        }
        return dateTime;
      })
      .toList(growable: false);
}

List<String?> _stringList(Object? value, String fieldName) {
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('รูปแบบข้อมูล $fieldName ไม่ถูกต้อง');
  }
  return value
      .map((item) {
        if (item != null && item is! String) {
          throw FormatException('รูปแบบข้อมูล $fieldName ไม่ถูกต้อง');
        }
        return item as String?;
      })
      .toList(growable: false);
}

List<bool?> _boolList(Object? value, String fieldName) {
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('รูปแบบข้อมูล $fieldName ไม่ถูกต้อง');
  }
  return value
      .map((item) {
        if (item != null && item is! bool) {
          throw FormatException('รูปแบบข้อมูล $fieldName ไม่ถูกต้อง');
        }
        return item as bool?;
      })
      .toList(growable: false);
}
