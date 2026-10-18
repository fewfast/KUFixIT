import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:latlong2/latlong.dart' as latlong;

import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';
import 'building_locations.dart';

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
  final Set<String> _deletingTechnicianUids = {};
  String? _techniciansError;
  String? _operationError;
  String _searchQuery = '';
  int _technicianPage = 0;
  static const int _techniciansPerPage = 5;
  String? _selectedTechnicianUid;
  List<_AssignedTicket> _assignedTickets = [];
  bool _isLoadingAssignedTickets = false;
  String? _assignedTicketsError;
  int _assignedTicketPage = 0;
  static const int _assignedTicketsPerPage = 5;
  String? _expandedAssignedTicketId;

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
        if (_selectedTechnicianUid != null &&
            !technicians.any(
              (technician) => technician.uid == _selectedTechnicianUid,
            )) {
          _selectedTechnicianUid = null;
          _assignedTickets = [];
          _expandedAssignedTicketId = null;
          _isLoadingAssignedTickets = false;
          _assignedTicketsError = null;
          _assignedTicketPage = 0;
        }
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

  Future<void> _selectTechnicianTickets(String? technicianUid) async {
    setState(() {
      _selectedTechnicianUid = technicianUid;
      _assignedTickets = [];
      _assignedTicketsError = null;
      _assignedTicketPage = 0;
      _expandedAssignedTicketId = null;
      _isLoadingAssignedTickets = technicianUid != null;
    });
    if (technicianUid == null) return;

    try {
      final data = await _invoke('list-technician-tickets', {
        'uid': technicianUid,
      });
      final rawTickets = data['tickets'];
      if (rawTickets is! List) {
        throw const FormatException('ไม่พบรายการ ticket ในข้อมูลตอบกลับ');
      }
      final tickets = rawTickets
          .map(_AssignedTicket.fromJson)
          .toList(growable: false);
      if (!mounted || _selectedTechnicianUid != technicianUid) return;
      setState(() {
        _assignedTickets = tickets;
        _isLoadingAssignedTickets = false;
      });
    } catch (error) {
      if (!mounted || _selectedTechnicianUid != technicianUid) return;
      setState(() {
        _assignedTicketsError = _errorText(error);
        _isLoadingAssignedTickets = false;
      });
    }
  }

  Future<void> _showTicketMap(_AssignedTicket ticket) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return AlertDialog(
          title: Text('ตำแหน่ง ticket ${ticket.ticketId}'),
          content: SizedBox(
            width: (size.width - 64).clamp(260.0, 720.0).toDouble(),
            height: (size.height - 220).clamp(240.0, 520.0).toDouble(),
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
                  'Latitude: ${ticket.latitude.toStringAsFixed(6)}  '
                  'Longitude: ${ticket.longitude.toStringAsFixed(6)}',
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
        );
      },
    );
  }

  Future<void> _showDevicePhoto(
    _AssignedTicket ticket,
    _TicketDevice device,
  ) async {
    final photoUrl = device.photoUrl;
    if (photoUrl == null) {
      _showMessage('ไม่พบรูปอุปกรณ์ ${device.deviceId} ของ ticket นี้');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('รูปอุปกรณ์ ${device.deviceId} · ${ticket.ticketId}'),
        content: Image.network(
          photoUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox(
            height: 220,
            child: Center(child: Text('โหลดรูปอุปกรณ์ไม่สำเร็จ')),
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

  Future<void> _editTicketDevice(
    _AssignedTicket ticket,
    _TicketDevice device,
  ) async {
    final uid = _selectedTechnicianUid;
    if (uid == null) return;

    final formKey = GlobalKey<FormState>();
    final deviceController = TextEditingController(text: device.name ?? '');
    final descriptionController = TextEditingController(
      text: device.description ?? '',
    );
    try {
      final request = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('แก้ไขอุปกรณ์ ${device.deviceId}'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: deviceController,
                    decoration: const InputDecoration(
                      labelText: 'ชื่ออุปกรณ์',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'คำอธิบาย',
                      border: OutlineInputBorder(),
                    ),
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
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'device': deviceController.text.trim(),
                  'description': descriptionController.text.trim(),
                });
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      );
      if (request == null || !mounted) return;

      final result = await _invoke('update-assigned-device', {
        'uid': uid,
        'ticketId': ticket.ticketId,
        'deviceId': device.deviceId,
        'request': request,
      });
      if (result['updated'] != true) {
        throw const FormatException('ไม่ได้รับการยืนยันการแก้ไขอุปกรณ์');
      }
      await _selectTechnicianTickets(uid);
      if (!mounted) return;
      setState(() => _expandedAssignedTicketId = ticket.ticketId);
      _showMessage('แก้ไขอุปกรณ์เรียบร้อยแล้ว');
    } catch (error) {
      if (mounted) {
        _showMessage('แก้ไขอุปกรณ์ไม่สำเร็จ: ${_errorText(error)}');
      }
    } finally {
      deviceController.dispose();
      descriptionController.dispose();
    }
  }

  Future<latlong.LatLng?> _chooseTicketLocation(
    latlong.LatLng initialLocation,
  ) async {
    var selectedLocation = initialLocation;
    return showDialog<latlong.LatLng>(
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
                      initialCenter: selectedLocation,
                      initialZoom: 16,
                      onTap: (_, position) =>
                          setDialogState(() => selectedLocation = position),
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
                            point: selectedLocation,
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
                  'Latitude: ${selectedLocation.latitude.toStringAsFixed(6)}  '
                  'Longitude: ${selectedLocation.longitude.toStringAsFixed(6)}',
                ),
                const Text('แตะบนแผนที่เพื่อเปลี่ยนตำแหน่ง'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedLocation),
              child: const Text('เลือกตำแหน่งนี้'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAssignedTicket(_AssignedTicket ticket) async {
    final uid = _selectedTechnicianUid;
    if (uid == null) return;

    final formKey = GlobalKey<FormState>();
    final initialBuilding = ticket.building == 'other'
        ? otherBuildingLabel
        : buildingOptions.firstWhere(
            (building) =>
                RegExp(r'\d+').firstMatch(building)?.group(0) ==
                ticket.building,
            orElse: () => '',
          );
    var selectedBuilding = initialBuilding.isEmpty ? null : initialBuilding;
    var selectedCoordinates = latlong.LatLng(ticket.latitude, ticket.longitude);
    if (selectedBuilding != null && selectedBuilding != otherBuildingLabel) {
      final buildingNumber = RegExp(
        r'\d+',
      ).firstMatch(selectedBuilding)?.group(0);
      final coordinates = buildingCoordinates[buildingNumber];
      if (coordinates != null) {
        selectedCoordinates = latlong.LatLng(coordinates.$1, coordinates.$2);
      }
    }
    final areaController = TextEditingController(text: ticket.area ?? '');
    final floorController = TextEditingController(text: ticket.floor ?? '');
    final roomController = TextEditingController(text: ticket.room ?? '');
    try {
      final request = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text('แก้ไข ticket ${ticket.ticketId}'),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Autocomplete<String>(
                        initialValue: TextEditingValue(
                          text: selectedBuilding ?? '',
                        ),
                        optionsBuilder: (value) {
                          final query = value.text.trim().toLowerCase();
                          if (query.isEmpty) return buildingOptions;
                          return buildingOptions.where(
                            (building) =>
                                building.toLowerCase().contains(query),
                          );
                        },
                        onSelected: (building) {
                          setDialogState(() {
                            selectedBuilding = building;
                            if (building == otherBuildingLabel) {
                              areaController.text = ticket.area ?? '';
                            } else {
                              areaController.clear();
                              final number = RegExp(
                                r'\d+',
                              ).firstMatch(building)?.group(0);
                              final coordinates = buildingCoordinates[number];
                              if (coordinates != null) {
                                selectedCoordinates = latlong.LatLng(
                                  coordinates.$1,
                                  coordinates.$2,
                                );
                              }
                            }
                          });
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onSubmitted) =>
                                TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    labelText: 'อาคาร',
                                    hintText: 'พิมพ์เพื่อค้นหาอาคาร',
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(Icons.arrow_drop_down),
                                  ),
                                  validator: (_) => selectedBuilding == null
                                      ? 'กรุณาเลือกอาคารจากรายการ'
                                      : null,
                                  onChanged: (_) {
                                    if (selectedBuilding != null) {
                                      setDialogState(
                                        () => selectedBuilding = null,
                                      );
                                    }
                                  },
                                  onFieldSubmitted: (_) => onSubmitted(),
                                ),
                      ),
                      if (selectedBuilding == otherBuildingLabel) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: areaController,
                          decoration: const InputDecoration(
                            labelText: 'ระบุชื่อตำแหน่ง',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value?.trim().isNotEmpty == true
                              ? null
                              : 'กรุณากรอกบริเวณ',
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final coordinates = await _chooseTicketLocation(
                              selectedCoordinates,
                            );
                            if (coordinates != null) {
                              setDialogState(
                                () => selectedCoordinates = coordinates,
                              );
                            }
                          },
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('เลือกตำแหน่งบนแผนที่'),
                        ),
                      ] else if (selectedBuilding != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'พิกัดจะใช้ตำแหน่งของอาคารที่เลือก\n'
                            'Latitude: ${selectedCoordinates.latitude.toStringAsFixed(6)}  '
                            'Longitude: ${selectedCoordinates.longitude.toStringAsFixed(6)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      TextFormField(
                        controller: floorController,
                        decoration: const InputDecoration(labelText: 'ชั้น'),
                        validator: (value) {
                          final floor = value?.trim() ?? '';
                          if (floor.isNotEmpty &&
                              (!RegExp(r'^\d{1,2}$').hasMatch(floor) ||
                                  int.parse(floor) > 50)) {
                            return 'กรอกชั้นตั้งแต่ 0 ถึง 50';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: roomController,
                        decoration: const InputDecoration(labelText: 'ห้อง'),
                        validator: (value) {
                          final room = value?.trim() ?? '';
                          return room.isEmpty ||
                                  RegExp(r'^[a-zA-Z0-9-]{1,8}$').hasMatch(room)
                              ? null
                              : 'ห้องใช้ตัวอักษรอังกฤษ ตัวเลข หรือ - ไม่เกิน 8 ตัว';
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final building = selectedBuilding!;
                  final isOtherBuilding = building == otherBuildingLabel;
                  final buildingNumber = RegExp(
                    r'\d+',
                  ).firstMatch(building)?.group(0);
                  Navigator.pop(dialogContext, {
                    'building': isOtherBuilding ? 'other' : buildingNumber,
                    'area': isOtherBuilding ? areaController.text.trim() : null,
                    'floor': floorController.text.trim(),
                    'room': roomController.text.trim(),
                    'latitude': selectedCoordinates.latitude,
                    'longitude': selectedCoordinates.longitude,
                  });
                },
                child: const Text('บันทึก'),
              ),
            ],
          ),
        ),
      );
      if (request == null || !mounted) return;

      final result = await _invoke('update-assigned-ticket', {
        'uid': uid,
        'ticketId': ticket.ticketId,
        'request': request,
      });
      if (result['updated'] != true) {
        throw const FormatException('ไม่ได้รับการยืนยันการแก้ไข ticket');
      }
      await _selectTechnicianTickets(uid);
      if (mounted) _showMessage('แก้ไข ticket เรียบร้อยแล้ว');
    } catch (error) {
      if (mounted) {
        _showMessage('แก้ไข ticket ไม่สำเร็จ: ${_errorText(error)}');
      }
    } finally {
      areaController.dispose();
      floorController.dispose();
      roomController.dispose();
    }
  }

  Future<void> _removeAssignedTicket(_AssignedTicket ticket) async {
    final uid = _selectedTechnicianUid;
    if (uid == null) return;
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('นำ ticket ออกจากทีมช่าง'),
        content: Text(
          'ต้องการนำ ticket ${ticket.ticketId} ออกจากรายการงานของทีมช่างนี้หรือไม่? '
          'ข้อมูล ticket ใน FixList จะไม่ถูกลบ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('นำออก'),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !mounted) return;

    try {
      final result = await _invoke('remove-assigned-ticket', {
        'uid': uid,
        'ticketId': ticket.ticketId,
      });
      if (result['removed'] != true) {
        throw const FormatException('ไม่ได้รับการยืนยันการนำ ticket ออก');
      }
      await _selectTechnicianTickets(uid);
      if (mounted) _showMessage('นำ ticket ออกจากทีมช่างแล้ว');
    } catch (error) {
      if (mounted) {
        _showMessage('นำ ticket ออกไม่สำเร็จ: ${_errorText(error)}');
      }
    }
  }

  Future<void> _createTechnician() async {
    final teamName = _technicianNameController.text.trim();
    final username = _usernameController.text.trim();
    final comment = _commentController.text.trim();
    if (teamName.isEmpty) {
      setState(() => _operationError = 'กรุณากรอกชื่อทีมช่าง');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_]{3,10}$').hasMatch(username)) {
      setState(
        () => _operationError =
            'username ต้องมี 3-10 ตัวอักษร และใช้ได้เฉพาะ A-Z, a-z, 0-9 หรือ _',
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
              onPressed: () => _copyText(
                'ชื่อทีมช่าง: $teamName\n'
                'username: $createdUsername\n'
                'password: $password',
              ),
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
    final orderedRanges = _sortDateRanges(ranges);
    if (_hasOverlappingDateRanges(orderedRanges)) {
      _showMessage('ช่วงวันที่เข้าใช้งานห้ามซ้ำหรือทับซ้อนกัน');
      return;
    }
    final dateRanges = orderedRanges
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
        title: const Text('แก้ไขชื่อทีมช่าง'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'ชื่อทีมช่าง'),
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
        _showMessage('ชื่อทีมช่างต้องไม่เว้นว่าง');
        return;
      }
      await _updateTechnician(technician, {'teamName': name});
    }
  }

  Future<void> _editTechnicianUsername(_Technician technician) async {
    final controller = TextEditingController(text: technician.username);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        final dialogWidth = (MediaQuery.sizeOf(context).width - 96)
            .clamp(200.0, 460.0)
            .toDouble();
        return AlertDialog(
          scrollable: true,
          title: const Text('แก้ไขชื่อผู้ใช้'),
          content: SizedBox(
            width: dialogWidth,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              ],
              decoration: const InputDecoration(
                labelText: 'ชื่อผู้ใช้',
                helperText: 'ใช้ตัวอักษรอังกฤษ ตัวเลข หรือ _ (3-10 ตัว)',
                helperMaxLines: 2,
              ),
            ),
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
        );
      },
    );
    controller.dispose();
    if (value != null && value.trim() != technician.username) {
      final username = value.trim();
      if (!RegExp(r'^[A-Za-z0-9_]{3,10}$').hasMatch(username)) {
        _showMessage(
          'username ต้องมี 3-10 ตัวอักษร และใช้ได้เฉพาะ A-Z, a-z, 0-9 หรือ _',
        );
        return;
      }
      await _updateTechnician(technician, {'username': username});
    }
  }

  Future<void> _editTechnicianComment(_Technician technician) async {
    final controller = TextEditingController(text: technician.comment);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        final dialogWidth = (MediaQuery.sizeOf(context).width - 96)
            .clamp(200.0, 460.0)
            .toDouble();
        return AlertDialog(
          scrollable: true,
          title: const Text('แก้ไขข้อมูลช่าง'),
          content: SizedBox(
            width: dialogWidth,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 1000,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'ข้อมูลช่าง',
                helperText: 'พิมพ์ได้หลายบรรทัด',
                helperMaxLines: 2,
                alignLabelWithHint: true,
              ),
            ),
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
        );
      },
    );
    controller.dispose();
    if (value != null && value.trim() != technician.comment) {
      final comment = value.trim();
      if (comment.isEmpty) {
        _showMessage('กรุณากรอกข้อมูลช่าง');
        return;
      }
      if (comment.length > 1000) {
        _showMessage('ข้อมูลช่างต้องไม่เกิน 1,000 ตัวอักษร');
        return;
      }
      await _updateTechnician(technician, {'comment': comment});
    }
  }

  Future<void> _editDateRanges(_Technician technician) async {
    var ranges = _sortDateRanges(technician.dateRanges);
    String? rangeError;
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
                                  ranges = _sortDateRanges(ranges);
                                  rangeError = null;
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
                                  ranges = _sortDateRanges(ranges);
                                  rangeError = null;
                                });
                              },
                              child: Text(
                                'สิ้นสุด ${_formatDateOnly(ranges[i].end)}',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'ลบช่วงวันที่',
                            onPressed: () => setDialogState(() {
                              ranges.removeAt(i);
                              rangeError = null;
                            }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => setDialogState(() {
                      final today = _todayInBangkok();
                      ranges.add(_DateRange(start: today, end: today));
                      ranges = _sortDateRanges(ranges);
                      rangeError = null;
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มช่วงวันที่'),
                  ),
                  if (rangeError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        rangeError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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
              onPressed: () {
                final orderedRanges = _sortDateRanges(ranges);
                if (_hasOverlappingDateRanges(orderedRanges)) {
                  setDialogState(() {
                    rangeError = 'ช่วงวันที่เข้าใช้งานห้ามซ้ำหรือทับซ้อนกัน';
                  });
                  return;
                }
                Navigator.pop(dialogContext, orderedRanges);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await _updateDateRanges(technician, result);
  }

  List<_DateRange> _sortDateRanges(List<_DateRange> ranges) {
    final sorted = ranges.toList()
      ..sort((first, second) {
        final startOrder = first.start.compareTo(second.start);
        return startOrder != 0 ? startOrder : first.end.compareTo(second.end);
      });
    return sorted;
  }

  bool _hasOverlappingDateRanges(List<_DateRange> sortedRanges) {
    for (var index = 1; index < sortedRanges.length; index++) {
      if (!sortedRanges[index].start.isAfter(sortedRanges[index - 1].end)) {
        return true;
      }
    }
    return false;
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

  Future<void> _deleteTechnician(_Technician technician) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันลบบัญชีช่าง'),
        content: Text(
          'ต้องการลบบัญชี "${technician.teamName}" (${technician.username}) '
          'ใช่หรือไม่?\n\nบัญชีจะไม่สามารถเข้าสู่ระบบได้อีก '
          'และประวัติงานซ่อมที่บันทึกไว้จะยังคงอยู่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('ลบบัญชี'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    setState(() => _deletingTechnicianUids.add(technician.uid));
    try {
      final data = await _invoke('delete-technician', {'uid': technician.uid});
      if (data['deleted'] != true) {
        throw const FormatException('ไม่ได้รับการยืนยันการลบบัญชีช่าง');
      }
      await _loadTechnicians();
      if (!mounted) return;
      if (_techniciansError != null) {
        _showMessage('ลบบัญชีสำเร็จ แต่โหลดรายการช่างใหม่ไม่สำเร็จ');
        return;
      }
      _showMessage('ลบบัญชีช่างเรียบร้อยแล้ว');
    } catch (error) {
      _showMessage('ลบบัญชีช่างไม่สำเร็จ: ${_errorText(error)}');
    } finally {
      if (mounted) {
        setState(() => _deletingTechnicianUids.remove(technician.uid));
      }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return Column(
            children: [
              for (final technician in technicians) _technicianCard(technician),
            ],
          );
        }

        const horizontalMargin = 12.0;
        const columnSpacing = 8.0;
        final columnWidth =
            constraints.maxWidth - horizontalMargin * 2 - columnSpacing * 7;
        final widths = [
          columnWidth * 0.10,
          columnWidth * 0.14,
          columnWidth * 0.12,
          columnWidth * 0.18,
          columnWidth * 0.06,
          columnWidth * 0.24,
          columnWidth * 0.07,
          columnWidth * 0.09,
        ];
        return SizedBox(
          width: constraints.maxWidth,
          child: DataTable(
            border: TableBorder(
              verticalInside: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            horizontalMargin: horizontalMargin,
            columnSpacing: columnSpacing,
            columns: [
              DataColumn(
                label: const Text('สร้างเมื่อ'),
                columnWidth: FixedColumnWidth(widths[0]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
              DataColumn(
                label: const Text('UID ช่าง'),
                columnWidth: FixedColumnWidth(widths[1]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
              DataColumn(
                label: const Text('ชื่อทีมช่าง'),
                columnWidth: FixedColumnWidth(widths[2]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
              DataColumn(
                label: const Text('ชื่อผู้ใช้'),
                columnWidth: FixedColumnWidth(widths[3]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
              DataColumn(
                label: const Text('รหัสผ่าน'),
                columnWidth: FixedColumnWidth(widths[4]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
              DataColumn(
                label: const Text('ข้อมูลช่าง'),
                columnWidth: FixedColumnWidth(widths[5]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
              DataColumn(
                label: const Text('จัดเวลา'),
                columnWidth: FixedColumnWidth(widths[6]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
              DataColumn(
                label: const Text('ลบบัญชี'),
                columnWidth: FixedColumnWidth(widths[7]),
                headingRowAlignment: MainAxisAlignment.center,
              ),
            ],
            rows: [
              for (final technician in technicians)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        _formatDate(technician.createdAt),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DataCell(
                      _copyableText(technician.uid, tooltip: 'คัดลอก UID ช่าง'),
                    ),
                    DataCell(
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              technician.teamName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'แก้ไขชื่อทีมช่าง',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onPressed: () => _editTechnicianName(technician),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              technician.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'แก้ไขชื่อผู้ใช้',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onPressed: () =>
                                _editTechnicianUsername(technician),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'คัดลอกชื่อผู้ใช้',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onPressed: () => _copyText(technician.username),
                            icon: const Icon(Icons.copy, size: 18),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Align(
                        alignment: Alignment.center,
                        child: IconButton(
                          tooltip: 'คัดลอกรหัสผ่าน',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          onPressed: () => _copyText(technician.password),
                          icon: const Icon(Icons.copy, size: 18),
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: technician.comment,
                              child: Text(
                                technician.comment.isEmpty
                                    ? '-'
                                    : technician.comment,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'แก้ไขข้อมูลช่าง',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                              height: 32,
                            ),
                            onPressed: () => _editTechnicianComment(technician),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Align(
                        alignment: Alignment.center,
                        child: IconButton(
                          tooltip: 'จัดเวลา',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          onPressed: () => _editDateRanges(technician),
                          icon: const Icon(Icons.edit_calendar_outlined),
                        ),
                      ),
                    ),
                    DataCell(
                      Align(
                        alignment: Alignment.center,
                        child: _deleteTechnicianButton(technician),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _copyableText(String value, {required String tooltip}) {
    return Row(
      children: [
        Expanded(
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          onPressed: () => _copyText(value),
          icon: const Icon(Icons.copy, size: 18),
        ),
      ],
    );
  }

  Widget _technicianCard(_Technician technician) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(technician.uid, maxLines: 1)),
                IconButton(
                  tooltip: 'คัดลอก UID ช่าง',
                  onPressed: () => _copyText(technician.uid),
                  icon: const Icon(Icons.copy),
                ),
                _deleteTechnicianButton(technician),
              ],
            ),
            _technicianCardValue(
              'สร้างเมื่อ',
              _formatDate(technician.createdAt),
            ),
            _technicianCardValue(
              'ชื่อทีมช่าง',
              technician.teamName,
              action: IconButton(
                tooltip: 'แก้ไขชื่อทีมช่าง',
                onPressed: () => _editTechnicianName(technician),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            _technicianCardValue(
              'ชื่อผู้ใช้',
              technician.username,
              action: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'แก้ไขชื่อผู้ใช้',
                    onPressed: () => _editTechnicianUsername(technician),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'คัดลอกชื่อผู้ใช้',
                    onPressed: () => _copyText(technician.username),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
            ),
            _technicianCardValue(
              'รหัสผ่าน',
              '',
              action: IconButton(
                tooltip: 'คัดลอกรหัสผ่าน',
                onPressed: () => _copyText(technician.password),
                icon: const Icon(Icons.copy, size: 18),
              ),
            ),
            _technicianCardValue(
              'ข้อมูลช่าง',
              technician.comment.isEmpty ? '-' : technician.comment,
              action: IconButton(
                tooltip: 'แก้ไขข้อมูลช่าง',
                onPressed: () => _editTechnicianComment(technician),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editDateRanges(technician),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('จัดเวลา'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _technicianCardValue(String label, String value, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, softWrap: true)),
          ?action,
        ],
      ),
    );
  }

  Widget _deleteTechnicianButton(_Technician technician) {
    final isDeleting = _deletingTechnicianUids.contains(technician.uid);
    return IconButton(
      tooltip: 'ลบบัญชีช่าง',
      onPressed: isDeleting ? null : () => _deleteTechnician(technician),
      color: Theme.of(context).colorScheme.error,
      icon: isDeleting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline),
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
    final pageCount = (visibleTechnicians.length / _techniciansPerPage).ceil();
    final currentPage = pageCount == 0
        ? 0
        : _technicianPage.clamp(0, pageCount - 1);
    final firstTechnicianIndex = currentPage * _techniciansPerPage;
    final pageTechnicians = visibleTechnicians
        .skip(firstTechnicianIndex)
        .take(_techniciansPerPage)
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
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'รายการงานตามทีมช่าง',
                  subtitle:
                      'เลือกทีมช่างเพื่อดู ticket ที่มอบหมายและตำแหน่งงาน',
                  child: _assignedTicketsSection(),
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'สร้างผู้ใช้ช่าง',
                  subtitle:
                      'กำหนดชื่อทีมช่าง username และข้อมูลช่าง ระบบจะสร้าง UID และรหัสผ่านให้',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _technicianNameController,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อทีมช่าง',
                          helperText: 'จำเป็นต้องกรอก',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _usernameController,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'username',
                          helperText:
                              'ใช้ตัวอักษรอังกฤษ ตัวเลข หรือ _ (3-10 ตัว)',
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
                          labelText: 'ข้อมูลช่าง',
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
                  subtitle: 'ค้นหาด้วยชื่อทีมช่าง username UID หรือข้อมูลช่าง',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'ค้นหาช่าง',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() {
                          _searchQuery = value;
                          _technicianPage = 0;
                        }),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingTechnicians)
                        const LinearProgressIndicator()
                      else if (_techniciansError != null)
                        _errorMessage(_techniciansError!, _loadTechnicians)
                      else
                        Column(
                          children: [
                            _technicianTable(pageTechnicians),
                            if (visibleTechnicians.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip: 'หน้าก่อนหน้า',
                                      onPressed: currentPage > 0
                                          ? () => setState(
                                              () => _technicianPage--,
                                            )
                                          : null,
                                      icon: const Icon(Icons.chevron_left),
                                    ),
                                    Text(
                                      'หน้า ${currentPage + 1} / $pageCount'
                                      '  ·  แสดง ${firstTechnicianIndex + 1}–'
                                      '${firstTechnicianIndex + pageTechnicians.length}'
                                      ' จาก ${visibleTechnicians.length} ทีม',
                                    ),
                                    IconButton(
                                      tooltip: 'หน้าถัดไป',
                                      onPressed: currentPage < pageCount - 1
                                          ? () => setState(
                                              () => _technicianPage++,
                                            )
                                          : null,
                                      icon: const Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
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

  Widget _assignedTicketTable(List<_AssignedTicket> tickets) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalMargin = 12.0;
        const columnSpacing = 8.0;
        final tableWidth = constraints.maxWidth < 1050
            ? 1050.0
            : constraints.maxWidth;
        final usableWidth =
            tableWidth - horizontalMargin * 2 - columnSpacing * 8;
        final widths = [
          usableWidth * 0.17,
          usableWidth * 0.11,
          usableWidth * 0.10,
          usableWidth * 0.08,
          usableWidth * 0.10,
          usableWidth * 0.07,
          usableWidth * 0.07,
          usableWidth * 0.08,
          usableWidth * 0.08,
        ];
        final selectedTicket = tickets.cast<_AssignedTicket?>().firstWhere(
          (ticket) => ticket?.ticketId == _expandedAssignedTicketId,
          orElse: () => null,
        );
        final tableBorder = TableBorder(
          verticalInside: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          horizontalInside: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DataTable(
                  border: tableBorder,
                  horizontalMargin: horizontalMargin,
                  columnSpacing: columnSpacing,
                  columns: [
                    for (var index = 0; index < 9; index++)
                      DataColumn(
                        label: Center(
                          child: Text(
                            const [
                              'ticketId',
                              'อาคาร',
                              'บริเวณ',
                              'ชั้นที่',
                              'เลขห้อง',
                              'แผนที่',
                              'แก้ไข',
                              'ถอดงาน',
                              'ขยายรายการ',
                            ][index],
                            textAlign: TextAlign.center,
                          ),
                        ),
                        columnWidth: FixedColumnWidth(widths[index]),
                        headingRowAlignment: MainAxisAlignment.center,
                      ),
                  ],
                  rows: [
                    for (final ticket in tickets)
                      DataRow(
                        color: WidgetStateProperty.resolveWith(
                          (states) =>
                              _expandedAssignedTicketId == ticket.ticketId
                              ? Theme.of(context).colorScheme.surfaceContainer
                              : null,
                        ),
                        cells: [
                          DataCell(
                            Center(
                              child: InkWell(
                                highlightColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                splashColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                                onTap: () => _copyText(ticket.ticketId),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(child: Text(ticket.ticketId)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.copy, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          DataCell(Center(child: Text(ticket.building))),
                          DataCell(Center(child: Text(ticket.area ?? '-'))),
                          DataCell(Center(child: Text(ticket.floor ?? '-'))),
                          DataCell(Center(child: Text(ticket.room ?? '-'))),
                          DataCell(
                            Center(
                              child: IconButton(
                                tooltip: 'เปิดแผนที่',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _showTicketMap(ticket),
                                icon: const Icon(Icons.map_outlined, size: 20),
                              ),
                            ),
                          ),
                          DataCell(
                            Center(
                              child: IconButton(
                                tooltip: 'แก้ไข ticket',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _editAssignedTicket(ticket),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                            ),
                          ),
                          DataCell(
                            Center(
                              child: IconButton(
                                tooltip: 'นำ ticket ออกจากทีมช่าง',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _removeAssignedTicket(ticket),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Center(
                              child: IconButton(
                                tooltip:
                                    _expandedAssignedTicketId == ticket.ticketId
                                    ? 'ซ่อนอุปกรณ์'
                                    : 'แสดงอุปกรณ์',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() {
                                  _expandedAssignedTicketId =
                                      _expandedAssignedTicketId ==
                                          ticket.ticketId
                                      ? null
                                      : ticket.ticketId;
                                }),
                                icon: Icon(
                                  _expandedAssignedTicketId == ticket.ticketId
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (selectedTicket != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'อุปกรณ์ใน ticket ${selectedTicket.ticketId}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  if (selectedTicket.devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('ไม่พบรายการอุปกรณ์'),
                    )
                  else
                    DataTable(
                      border: tableBorder,
                      horizontalMargin: horizontalMargin,
                      columnSpacing: columnSpacing,
                      columns: [
                        DataColumn(
                          label: Center(child: Text('ชื่ออุปกรณ์')),
                          headingRowAlignment: MainAxisAlignment.center,
                          columnWidth: const FlexColumnWidth(1),
                        ),
                        DataColumn(
                          label: Center(child: Text('คำอธิบาย')),
                          headingRowAlignment: MainAxisAlignment.center,
                          columnWidth: const FlexColumnWidth(2),
                        ),
                        DataColumn(
                          label: Center(
                            child: Text(
                              'รูป\nอุปกรณ์',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          headingRowAlignment: MainAxisAlignment.center,
                          columnWidth: const FixedColumnWidth(72),
                        ),
                        DataColumn(
                          label: Center(child: Text('แก้ไข')),
                          headingRowAlignment: MainAxisAlignment.center,
                          columnWidth: const FixedColumnWidth(72),
                        ),
                      ],
                      rows: [
                        for (final device in selectedTicket.devices)
                          DataRow(
                            cells: [
                              DataCell(Center(child: Text(device.name ?? '-'))),
                              DataCell(
                                Center(child: Text(device.description ?? '-')),
                              ),
                              DataCell(
                                Center(
                                  child: IconButton(
                                    tooltip: 'ดูรูปอุปกรณ์',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _showDevicePhoto(
                                      selectedTicket,
                                      device,
                                    ),
                                    icon: const Icon(
                                      Icons.photo_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Center(
                                  child: IconButton(
                                    tooltip: 'แก้ไขอุปกรณ์',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _editTicketDevice(
                                      selectedTicket,
                                      device,
                                    ),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _assignedTicketsSection() {
    final pageCount = (_assignedTickets.length / _assignedTicketsPerPage)
        .ceil();
    final currentPage = pageCount == 0
        ? 0
        : _assignedTicketPage.clamp(0, pageCount - 1);
    final firstTicketIndex = currentPage * _assignedTicketsPerPage;
    final pageTickets = _assignedTickets
        .skip(firstTicketIndex)
        .take(_assignedTicketsPerPage)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownMenu<String>(
          key: ValueKey(_selectedTechnicianUid),
          initialSelection: _selectedTechnicianUid,
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          requestFocusOnTap: true,
          label: const Text('เลือกทีมช่าง'),
          dropdownMenuEntries: _technicians
              .map(
                (technician) => DropdownMenuEntry<String>(
                  value: technician.uid,
                  label: technician.teamName,
                ),
              )
              .toList(growable: false),
          onSelected: _isLoadingTechnicians ? null : _selectTechnicianTickets,
        ),
        if (_isLoadingTechnicians) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (_isLoadingAssignedTickets) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ] else if (_assignedTicketsError != null) ...[
          const SizedBox(height: 8),
          _errorMessage(
            _assignedTicketsError!,
            () => _selectTechnicianTickets(_selectedTechnicianUid),
          ),
        ] else if (_selectedTechnicianUid != null) ...[
          const SizedBox(height: 12),
          if (_assignedTickets.isEmpty)
            const Text('ทีมช่างนี้ยังไม่มี ticket ที่มอบหมาย')
          else
            _assignedTicketTable(pageTickets),
          if (_assignedTickets.isNotEmpty)
            Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'หน้าก่อนหน้า',
                    onPressed: currentPage > 0
                        ? () => setState(() => _assignedTicketPage--)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    'หน้า ${currentPage + 1} / $pageCount  ·  '
                    'แสดง ${firstTicketIndex + 1}–'
                    '${firstTicketIndex + pageTickets.length} '
                    'จาก ${_assignedTickets.length} รายการ',
                  ),
                  IconButton(
                    tooltip: 'หน้าถัดไป',
                    onPressed: currentPage < pageCount - 1
                        ? () => setState(() => _assignedTicketPage++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      ],
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

class _AssignedTicket {
  const _AssignedTicket({
    required this.ticketId,
    required this.building,
    required this.area,
    required this.floor,
    required this.room,
    required this.devices,
    required this.longitude,
    required this.latitude,
  });

  final String ticketId;
  final String building;
  final String? area;
  final String? floor;
  final String? room;
  final List<_TicketDevice> devices;
  final double longitude;
  final double latitude;

  factory _AssignedTicket.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('ข้อมูล ticket ไม่ถูกต้อง');
    }
    final data = Map<String, Object?>.from(value);
    final ticketId = data['TicketId'];
    final building = data['building'];
    final longitude = data['longtitude'];
    final latitude = data['latitude'];
    final area = data['area'];
    final floor = data['floor'];
    final room = data['room'];
    final devices = data['devices'];
    if (ticketId is! String ||
        !RegExp(r'^\d{10}$').hasMatch(ticketId) ||
        building is! String ||
        longitude is! num ||
        latitude is! num ||
        (area != null && area is! String) ||
        (floor != null && floor is! String) ||
        (room != null && room is! String) ||
        devices is! List) {
      throw const FormatException('ข้อมูล ticket ไม่ครบถ้วน');
    }
    final ticketDevices = devices
        .map(_TicketDevice.fromJson)
        .toList(growable: false);
    final parsedLongitude = longitude.toDouble();
    final parsedLatitude = latitude.toDouble();
    if (!parsedLongitude.isFinite ||
        !parsedLatitude.isFinite ||
        parsedLongitude < -180 ||
        parsedLongitude > 180 ||
        parsedLatitude < -90 ||
        parsedLatitude > 90) {
      throw const FormatException('พิกัดของ ticket ไม่ถูกต้อง');
    }
    return _AssignedTicket(
      ticketId: ticketId,
      building: building,
      area: area as String?,
      floor: floor as String?,
      room: room as String?,
      devices: ticketDevices,
      longitude: parsedLongitude,
      latitude: parsedLatitude,
    );
  }
}

class _TicketDevice {
  const _TicketDevice({
    required this.deviceId,
    required this.name,
    required this.description,
    required this.photoUrl,
  });

  final int deviceId;
  final String? name;
  final String? description;
  final String? photoUrl;

  factory _TicketDevice.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('ข้อมูลอุปกรณ์ไม่ถูกต้อง');
    }
    final data = Map<String, Object?>.from(value);
    final deviceId = data['deviceid'];
    final name = data['device'];
    final description = data['discription'];
    final photoUrl = data['devicePhotoUrl'];
    if (deviceId is! int ||
        deviceId < 1 ||
        (name != null && name is! String) ||
        (description != null && description is! String) ||
        (photoUrl != null && photoUrl is! String)) {
      throw const FormatException('ข้อมูลอุปกรณ์ไม่ครบถ้วน');
    }
    return _TicketDevice(
      deviceId: deviceId,
      name: name as String?,
      description: description as String?,
      photoUrl: photoUrl as String?,
    );
  }
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  _DateRange copyWith({DateTime? start, DateTime? end}) =>
      _DateRange(start: start ?? this.start, end: end ?? this.end);
}
