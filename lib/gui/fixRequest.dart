import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../auth/temporary_account_session.dart';
import '../database/connect.dart';
import 'building_locations.dart';

// OpenStreetMap campus centroid: https://www.openstreetmap.org/way/1408248543
const _campusCenter = LatLng(13.1209646, 100.9192182);

class FixRequestPage extends StatefulWidget {
  const FixRequestPage({super.key});

  @override
  State<FixRequestPage> createState() => _FixRequestPageState();
}

class _FixRequestPageState extends State<FixRequestPage> {
  static const _maxPhotoBytes = 2 * 1024 * 1024;
  final _formKey = GlobalKey<FormState>();
  final _buildingFieldKey = GlobalKey();
  final _otherLocationFieldKey = GlobalKey();
  final _floorFieldKey = GlobalKey<FormFieldState<String>>();
  final _roomFieldKey = GlobalKey<FormFieldState<String>>();
  final _locationPickerButtonKey = GlobalKey();
  final _imagePicker = ImagePicker();
  final _floorController = TextEditingController();
  final _roomController = TextEditingController();
  final _otherLocationController = TextEditingController();
  Key _buildingAutocompleteKey = UniqueKey();
  String _buildingText = '';
  String? _selectedBuilding;
  String? _buildingError;
  String? _otherLocationError;
  LatLng? _selectedCoordinates;
  String? _coordinateError;
  bool _isSubmitting = false;
  final List<_RepairItem> _repairItems = [_RepairItem()];

  @override
  void dispose() {
    _floorController.dispose();
    _roomController.dispose();
    _otherLocationController.dispose();
    for (final item in _repairItems) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _choosePhoto(_RepairItem item) async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      _imageContentType(image.name);
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxPhotoBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รูปต้องมีขนาดไม่เกิน 2 MB')),
        );
        return;
      }
      setState(() {
        item.photoName = image.name;
        item.photoBytes = bytes;
        item.photoError = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เลือกรูปไม่สำเร็จ: $error')));
    }
  }

  void _addRepairItem() {
    setState(() => _repairItems.add(_RepairItem()));
  }

  void _removeRepairItem(_RepairItem item) {
    if (_repairItems.length == 1) return;
    setState(() {
      _repairItems.remove(item);
      item.dispose();
    });
  }

  Future<void> _submitRequest() async {
    if (_isSubmitting) return;
    final isBuildingMissing = _selectedBuilding == null;
    final isOtherLocation = _selectedBuilding == otherBuildingLabel;
    setState(() {
      _buildingError = isBuildingMissing ? 'กรุณาเลือกอาคารจากรายการ' : null;
      _otherLocationError =
          isOtherLocation && _otherLocationController.text.trim().isEmpty
          ? 'กรุณาระบุชื่อตำแหน่ง'
          : null;
      _coordinateError = isOtherLocation && _selectedCoordinates == null
          ? 'กรุณาเลือกตำแหน่งบนแผนที่'
          : null;
      for (final item in _repairItems) {
        item.photoError = item.photoBytes == null ? 'กรุณาแนบรูปถ่าย' : null;
      }
    });
    final isFormValid = _formKey.currentState!.validate();
    if (!isFormValid || _repairItems.any((item) => item.photoBytes == null)) {
      await _scrollToFirstInvalidField();
      return;
    }
    if (_selectedCoordinates == null) {
      setState(() => _coordinateError = 'กรุณาเลือกตำแหน่งบนแผนที่');
      await _scrollToFirstInvalidField();
      return;
    }

    final accessToken = TemporaryAccountSession.instance.account?.accessToken;
    if (accessToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนส่งคำร้อง')),
      );
      return;
    }

    final selectedBuilding = _selectedBuilding!;
    final building = isOtherLocation
        ? 'other'
        : RegExp(r'\d+').firstMatch(selectedBuilding)!.group(0)!;
    final coordinates = _selectedCoordinates!;
    final devices = _repairItems
        .map((item) {
          final photoBytes = item.photoBytes;
          final photoName = item.photoName;
          return {
            'floor': _optionalText(_floorController.text),
            'room': _optionalText(_roomController.text),
            'device': item.equipmentController.text.trim(),
            'description': _optionalText(item.detailsController.text),
            'photo': photoBytes == null
                ? null
                : {
                    'contentType': _imageContentType(photoName!),
                    'base64': base64Encode(photoBytes),
                  },
          };
        })
        .toList(growable: false);

    setState(() => _isSubmitting = true);
    try {
      if (!SupabaseConnection.isInitialized) {
        throw Exception('ยังไม่ได้เชื่อมต่อ Supabase');
      }
      final response = await SupabaseConnection.client.functions.invoke(
        'create-fix-request',
        headers: {'Authorization': 'Bearer $accessToken'},
        body: {
          'building': building,
          'area': isOtherLocation ? _otherLocationController.text.trim() : null,
          'longtitude': coordinates.longitude,
          'latitude': coordinates.latitude,
          'devices': devices,
        },
      );
      final result = response.data;
      if (result is! Map ||
          result['TicketId'] is! String ||
          result['PhotoCount'] != _repairItems.length) {
        throw const FormatException('ไม่ได้รับการยืนยันบันทึกรูปจากระบบ');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ส่งคำร้องสำเร็จ เลขที่ ${result['TicketId']} '
            'และบันทึกรูป ${result['PhotoCount']} รูป',
          ),
        ),
      );
      _clearForm();
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งคำร้องไม่สำเร็จ: $error')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _scrollToFirstInvalidField() async {
    final invalidFieldContext = _buildingError != null
        ? _buildingFieldKey.currentContext
        : _otherLocationError != null
        ? _otherLocationFieldKey.currentContext
        : _coordinateError != null
        ? _locationPickerButtonKey.currentContext
        : _floorFieldKey.currentState?.hasError == true
        ? _floorFieldKey.currentContext
        : _roomFieldKey.currentState?.hasError == true
        ? _roomFieldKey.currentContext
        : _firstInvalidRepairItemContext();

    if (invalidFieldContext != null) {
      await Scrollable.ensureVisible(
        invalidFieldContext,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
    }
  }

  BuildContext? _firstInvalidRepairItemContext() {
    for (final item in _repairItems) {
      if (item.equipmentFieldKey.currentState?.hasError == true) {
        return item.equipmentFieldKey.currentContext;
      }
      if (item.photoError != null) return item.photoButtonKey.currentContext;
    }
    return null;
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    for (final item in _repairItems) {
      item.dispose();
    }
    _otherLocationController.clear();
    _floorController.clear();
    _roomController.clear();
    setState(() {
      _repairItems
        ..clear()
        ..add(_RepairItem());
      _buildingText = '';
      _buildingAutocompleteKey = UniqueKey();
      _selectedBuilding = null;
      _selectedCoordinates = null;
      _coordinateError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validationStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Theme(
          data: theme.copyWith(
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              errorStyle: validationStyle,
            ),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'แจ้งซ่อม',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'เลือกอาคารและระบุรายละเอียดอุปกรณ์ที่ต้องการแจ้งซ่อม',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Autocomplete<String>(
                  key: _buildingAutocompleteKey,
                  initialValue: TextEditingValue(text: _buildingText),
                  optionsBuilder: (textEditingValue) {
                    final query = textEditingValue.text.trim().toLowerCase();
                    if (query.isEmpty) return buildingOptions;
                    return buildingOptions.where(
                      (building) => building.toLowerCase().contains(query),
                    );
                  },
                  onSelected: (building) {
                    setState(() {
                      _buildingText = building;
                      _selectedBuilding = building;
                      _buildingError = null;
                      _otherLocationError = null;
                      final buildingNumber = RegExp(
                        r'\d+',
                      ).firstMatch(building)?.group(0);
                      final coordinates = buildingCoordinates[buildingNumber];
                      _selectedCoordinates =
                          building == otherBuildingLabel || coordinates == null
                          ? null
                          : LatLng(coordinates.$1, coordinates.$2);
                      _coordinateError = null;
                      if (building != otherBuildingLabel) {
                        _otherLocationController.clear();
                      }
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _floorFieldKey.currentState?.validate();
                    });
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                        return TextFormField(
                          key: _buildingFieldKey,
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'อาคาร',
                            hintText: 'พิมพ์เพื่อค้นหาอาคาร',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.arrow_drop_down),
                            errorText: _buildingError,
                          ),
                          onChanged: (value) {
                            _buildingText = value;
                            if (_selectedBuilding != null) {
                              setState(() {
                                _selectedBuilding = null;
                                _buildingError = 'กรุณาเลือกอาคารจากรายการ';
                                _selectedCoordinates = null;
                                _coordinateError = null;
                              });
                            }
                          },
                          onFieldSubmitted: (_) => onFieldSubmitted(),
                        );
                      },
                ),
                if (_selectedBuilding != null &&
                    _selectedBuilding != otherBuildingLabel)
                  if (_selectedCoordinates case final coordinates?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Latitude: ${coordinates.latitude.toStringAsFixed(6)}  '
                        'Longitude: ${coordinates.longitude.toStringAsFixed(6)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                if (_selectedBuilding == otherBuildingLabel) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: _otherLocationFieldKey,
                    controller: _otherLocationController,
                    decoration: InputDecoration(
                      labelText: 'ระบุชื่อตำแหน่ง',
                      border: OutlineInputBorder(),
                      errorText: _otherLocationError,
                    ),
                    onChanged: (value) {
                      if (value.trim().isNotEmpty &&
                          _otherLocationError != null) {
                        setState(() => _otherLocationError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: _locationPickerButtonKey,
                    onPressed: _chooseLocation,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('เลือกตำแหน่งบนแผนที่'),
                  ),
                  if (_selectedCoordinates case final coordinates?)
                    Text(
                      'Latitude: ${coordinates.latitude.toStringAsFixed(6)}  '
                      'Longitude: ${coordinates.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                    )
                  else if (_coordinateError case final error?)
                    _validationMessage(error)
                  else
                    Text(
                      'ยังไม่ได้เลือกพิกัด',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  key: _floorFieldKey,
                  controller: _floorController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final floor = int.tryParse(newValue.text);
                      return floor != null && floor <= 50 ? newValue : oldValue;
                    }),
                  ],
                  decoration: InputDecoration(
                    labelText:
                        _selectedBuilding != null &&
                            _selectedBuilding != otherBuildingLabel
                        ? 'ชั้นที่ (จำเป็น, ไม่เกิน 50 ชั้น)'
                        : 'ชั้นที่ (ถ้ามี, ไม่เกิน 50 ชั้น)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final floor = value?.trim() ?? '';
                    if (floor.isEmpty) {
                      return _selectedBuilding != null &&
                              _selectedBuilding != otherBuildingLabel
                          ? 'กรุณาระบุชั้นที่'
                          : null;
                    }
                    final parsedFloor = int.tryParse(floor);
                    return parsedFloor != null && parsedFloor <= 50
                        ? null
                        : 'ชั้นต้องไม่เกิน 50';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: _roomFieldKey,
                  controller: _roomController,
                  keyboardType: TextInputType.text,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9-]')),
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'เลขห้อง (ถ้ามี)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final room = value?.trim() ?? '';
                    return room.isEmpty ||
                            RegExp(r'^[a-zA-Z0-9-]{1,8}$').hasMatch(room)
                        ? null
                        : 'เลขห้องต้องเป็นตัวอักษร ตัวเลข หรือ - ไม่เกิน 8 ตัว';
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'รายการอุปกรณ์ที่ชำรุด',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'เพิ่มรายการ',
                      onPressed: _isSubmitting ? null : _addRepairItem,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < _repairItems.length; index++) ...[
                  _buildRepairItemCard(_repairItems[index], index),
                  if (index < _repairItems.length - 1)
                    const SizedBox(height: 16),
                ],
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submitRequest,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _isSubmitting ? 'กำลังส่งคำร้อง...' : 'ส่งคำร้อง',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseLocation() async {
    final coordinates = await showDialog<LatLng>(
      context: context,
      builder: (context) =>
          _LocationPickerDialog(initialPosition: _selectedCoordinates),
    );
    if (coordinates == null || !mounted) return;
    setState(() {
      _selectedCoordinates = coordinates;
      _coordinateError = null;
    });
  }

  Widget _buildRepairItemCard(_RepairItem item, int index) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'รายการที่ ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (_repairItems.length > 1)
                  IconButton(
                    tooltip: 'ลบรายการที่ ${index + 1}',
                    onPressed: () => _removeRepairItem(item),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: item.equipmentFieldKey,
              controller: item.equipmentController,
              decoration: const InputDecoration(
                labelText: 'ชื่ออุปกรณ์ที่พัง',
                border: OutlineInputBorder(),
              ),
              validator: _requiredField,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: item.photoButtonKey,
              onPressed: () => _choosePhoto(item),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                item.photoName == null ? 'เพิ่มรูปถ่าย' : 'เปลี่ยนรูปถ่าย',
              ),
            ),
            if (item.photoError case final error?) ...[
              _validationMessage(error),
            ],
            if (item.photoBytes case final bytes?) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  bytes,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Text('แสดงรูปภาพไม่สำเร็จ'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    item.photoName = null;
                    item.photoBytes = null;
                    item.photoError = 'กรุณาแนบรูปถ่าย';
                  }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('ลบรูป'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: item.detailsController,
              decoration: const InputDecoration(
                labelText: 'ข้อมูลเพิ่มเติม',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _validationMessage(String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, top: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }

  String? _requiredField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'กรุณากรอกข้อมูล';
    }
    return null;
  }

  String? _optionalText(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String _imageContentType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => throw FormatException(
        'รองรับรูปภาพ JPG, PNG, GIF หรือ WEBP เท่านั้น',
      ),
    };
  }
}

class _LocationPickerDialog extends StatefulWidget {
  const _LocationPickerDialog({
    this.initialPosition,
  });

  final LatLng? initialPosition;

  @override
  State<_LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<_LocationPickerDialog> {
  LatLng? _selectedPosition;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    final position = _selectedPosition;
    return AlertDialog(
      title: const Text('เลือกตำแหน่ง'),
      content: SizedBox(
        width: 600,
        height: 420,
        child: Column(
          children: [
            Expanded(
              child: flutter_map.FlutterMap(
                options: flutter_map.MapOptions(
                  initialCenter: position ?? _campusCenter,
                  initialZoom: 16,
                  onTap: (_, value) => setState(
                    () => _selectedPosition = value,
                  ),
                ),
                children: [
                  flutter_map.TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.mobileproject',
                  ),
                  if (position case final selected?)
                    flutter_map.MarkerLayer(
                      markers: [
                        flutter_map.Marker(
                          point: selected,
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
              position == null
                  ? 'แตะบนแผนที่เพื่อเลือกตำแหน่ง'
                  : 'Latitude: ${position.latitude.toStringAsFixed(6)}  '
                        'Longitude: ${position.longitude.toStringAsFixed(6)}',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: position == null
              ? null
              : () => Navigator.pop(context, position),
          child: const Text('ยืนยันตำแหน่ง'),
        ),
      ],
    );
  }
}

class _RepairItem {
  final equipmentFieldKey = GlobalKey<FormFieldState<String>>();
  final photoButtonKey = GlobalKey();
  final equipmentController = TextEditingController();
  final detailsController = TextEditingController();
  String? photoName;
  Uint8List? photoBytes;
  String? photoError;

  void dispose() {
    equipmentController.dispose();
    detailsController.dispose();
  }
}
