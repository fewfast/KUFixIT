import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as latlong;

import '../auth/temporary_account_session.dart';
import '../database/connect.dart';

// OpenStreetMap campus centroid: https://www.openstreetmap.org/way/1408248543
const _campusCenter = LatLng(13.1209646, 100.9192182);
const _buildingCoordinates = {
  '1': LatLng(13.120900, 100.919218),
  '2': LatLng(13.120758, 100.920092),
  '3': LatLng(13.120429, 100.920714),
  '4': LatLng(13.120429, 100.920714),
  '5': LatLng(13.124191, 100.919240),
  '6': LatLng(13.120879, 100.920656),
  '7': LatLng(13.117671, 100.921063),
  '9': LatLng(13.117905, 100.920758),
  '10': LatLng(13.118544, 100.920377),
  '11': LatLng(13.124965, 100.919261),
  '12': LatLng(13.121722, 100.920111),
  '13': LatLng(13.123324, 100.918349),
  '14': LatLng(13.121924, 100.919250),
  '15': LatLng(13.120015, 100.919926),
  '16': LatLng(13.115229, 100.923787),
  '17': LatLng(13.119170, 100.919825),
  '18': LatLng(13.124756, 100.919749),
  '19': LatLng(13.117848, 100.921621),
  '20': LatLng(13.122828, 100.918167),
  '21': LatLng(13.124735, 100.918784),
  '22': LatLng(13.122748, 100.919202),
  '23': LatLng(13.119765, 100.920800),
  '24': LatLng(13.119295, 100.921053),
  '25': LatLng(13.118747, 100.921069),
  '26': LatLng(13.118784, 100.921412),
  '27': LatLng(13.118849, 100.920605),
  '28': LatLng(13.119372, 100.920327),
};

class FixRequestPage extends StatefulWidget {
  const FixRequestPage({super.key});

  @override
  State<FixRequestPage> createState() => _FixRequestPageState();
}

class _FixRequestPageState extends State<FixRequestPage> {
  static const _maxPhotoBytes = 2 * 1024 * 1024;
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _floorController = TextEditingController();
  final _roomController = TextEditingController();
  final _otherLocationController = TextEditingController();
  Key _buildingAutocompleteKey = UniqueKey();
  String? _selectedBuilding;
  LatLng? _selectedCoordinates;
  String? _coordinateError;
  bool _isSubmitting = false;
  final List<_RepairItem> _repairItems = [_RepairItem()];

  static const _otherBuilding = 'อื่นๆ';
  static const _buildings = [
    'อาคาร 1 บริการวิชาการ',
    'อาคาร 2 ปฏิบัติการวิศวกรรมศาสตร์',
    'อาคาร 3 ปฏิบัติการวิศวกรรมศาสตร์ภาคเรือและอากาศยาน',
    'อาคาร 4 พักอาศัยบุคลากร',
    'อาคาร 5 วิทยาศาสตร์พื้นฐาน',
    'อาคาร 6 ศูนย์เรียนรวม',
    'อาคาร 7 โรงอาหารกลาง',
    'อาคาร 9 ศูนย์กิจกรรม',
    'อาคาร 10 ศูนย์เรียนรวม 2',
    'อาคาร 11 สถานที่และยานพาหนะ',
    'อาคาร 12 ศรีธรรมเกษตร',
    'อาคาร 13 พลศึกษา',
    'อาคาร 14 หอสมุดอนุสรณ์ 10 ปี',
    'อาคาร 15 ปฏิบัติการวิทยาศาสตร์และเทคโนโลยี',
    'อาคาร 16 รักษาความปลอดภัย',
    'อาคาร 17 ศูนย์เรียนรวม 3',
    'อาคาร 18 เศรษฐศาสตร์ศรีราชา',
    'อาคาร 19 พักอาศัยบุคลากร 2',
    'อาคาร 20 สระว่ายน้ำ',
    'อาคาร 21 สนามฟุตบอล',
    'อาคาร 22 อาคารธุรกิจศึกษา',
    'อาคาร 23 อาคารคณะวิศวกรรมศาสตร์ศรีราชา',
    'อาคาร 24 อาคารคณะพาณิชยนาวีนานาชาติ',
    'อาคาร 25 ศูนย์คอมพิวเตอร์',
    'อาคาร 26 อาคารคณะวิทยาศาสตร์ ศรีราชา',
    'อาคาร 27 อาคารเรียนและปฏิบัติการพื้นฐานและเทคโนโลยี',
    'อาคาร 28 อาคารอเนกประสงค์และการประชุม',
    _otherBuilding,
  ];

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
    final isFormValid = _formKey.currentState!.validate();
    setState(() {
      for (final item in _repairItems) {
        item.photoError = item.photoBytes == null ? 'กรุณาแนบรูปถ่าย' : null;
      }
    });
    if (!isFormValid || _repairItems.any((item) => item.photoBytes == null)) {
      return;
    }
    if (_selectedCoordinates == null) {
      setState(() => _coordinateError = 'กรุณาเลือกตำแหน่งบนแผนที่');
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
    final isOtherLocation = selectedBuilding == _otherBuilding;
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
      _buildingAutocompleteKey = UniqueKey();
      _selectedBuilding = null;
      _selectedCoordinates = null;
      _coordinateError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
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
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) return _buildings;
                  return _buildings.where(
                    (building) => building.toLowerCase().contains(query),
                  );
                },
                onSelected: (building) {
                  setState(() {
                    _selectedBuilding = building;
                    final buildingNumber =
                        RegExp(r'\d+').firstMatch(building)?.group(0);
                    _selectedCoordinates = building == _otherBuilding
                        ? null
                        : _buildingCoordinates[buildingNumber];
                    _coordinateError = null;
                    if (building != _otherBuilding) {
                      _otherLocationController.clear();
                    }
                  });
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'อาคาร',
                          hintText: 'พิมพ์เพื่อค้นหาอาคาร',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        validator: (_) => _selectedBuilding == null
                            ? 'กรุณาเลือกอาคารจากรายการ'
                            : null,
                        onChanged: (_) {
                          if (_selectedBuilding != null) {
                            setState(() {
                              _selectedBuilding = null;
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
                  _selectedBuilding != _otherBuilding)
                if (_selectedCoordinates case final coordinates?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Latitude: ${coordinates.latitude.toStringAsFixed(6)}  '
                      'Longitude: ${coordinates.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
              if (_selectedBuilding == _otherBuilding) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _otherLocationController,
                  decoration: const InputDecoration(
                    labelText: 'ระบุชื่อตำแหน่ง',
                    border: OutlineInputBorder(),
                  ),
                  validator: _requiredField,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
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
                else
                  Text(
                    _coordinateError ?? 'ยังไม่ได้เลือกพิกัด',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _coordinateError == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _floorController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'ชั้นที่ (ถ้ามี)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _roomController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'เลขห้อง (ถ้ามี)',
                  border: OutlineInputBorder(),
                ),
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
                if (index < _repairItems.length - 1) const SizedBox(height: 16),
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
              controller: item.equipmentController,
              decoration: const InputDecoration(
                labelText: 'ชื่ออุปกรณ์ที่พัง',
                border: OutlineInputBorder(),
              ),
              validator: _requiredField,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _choosePhoto(item),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                item.photoName == null ? 'เพิ่มรูปถ่าย' : 'เปลี่ยนรูปถ่าย',
              ),
            ),
            if (item.photoError case final error?) ...[
              const SizedBox(height: 4),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
  const _LocationPickerDialog({this.initialPosition});

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
    final isGoogleMapsSupported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return AlertDialog(
      title: const Text('เลือกตำแหน่ง'),
      content: SizedBox(
        width: 600,
        height: 420,
        child: Column(
          children: [
            Expanded(
              child: isGoogleMapsSupported
                  ? GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: position ?? _campusCenter,
                        zoom: 16,
                      ),
                      markers: {
                        if (position case final selected?)
                          Marker(
                            markerId: const MarkerId('selected-location'),
                            position: selected,
                            draggable: true,
                            onDragEnd: (value) =>
                                setState(() => _selectedPosition = value),
                          ),
                      },
                      onTap: (value) =>
                          setState(() => _selectedPosition = value),
                    )
                  : flutter_map.FlutterMap(
                      options: flutter_map.MapOptions(
                        initialCenter: position == null
                            ? latlong.LatLng(
                                _campusCenter.latitude,
                                _campusCenter.longitude,
                              )
                            : latlong.LatLng(
                                position.latitude,
                                position.longitude,
                              ),
                        initialZoom: 16,
                        onTap: (_, value) => setState(
                          () => _selectedPosition = LatLng(
                            value.latitude,
                            value.longitude,
                          ),
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
                                point: latlong.LatLng(
                                  selected.latitude,
                                  selected.longitude,
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
