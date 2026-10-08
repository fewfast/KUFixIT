import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as latlong;

class FixRequestPage extends StatefulWidget {
  const FixRequestPage({super.key});

  @override
  State<FixRequestPage> createState() => _FixRequestPageState();
}

class _FixRequestPageState extends State<FixRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _otherLocationController = TextEditingController();
  String? _selectedBuilding;
  LatLng? _selectedCoordinates;
  String? _coordinateError;
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
    'อาคาร 29 อาคารปฏิบัติการไฟฟ้าแรงสูง',
    _otherBuilding,
  ];

  @override
  void dispose() {
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
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        item.photoName = image.name;
        item.photoBytes = bytes;
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

  void _submitRequest() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBuilding == _otherBuilding && _selectedCoordinates == null) {
      setState(() => _coordinateError = 'กรุณาเลือกตำแหน่งบนแผนที่');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ตรวจสอบข้อมูลแล้ว แต่ระบบส่งคำร้องและอัปโหลดรูปยังไม่เชื่อมต่อ',
        ),
      ),
    );
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
                    if (building != _otherBuilding) {
                      _selectedCoordinates = null;
                      _coordinateError = null;
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
                    onPressed: _addRepairItem,
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
                  onPressed: _submitRequest,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('ส่งคำร้อง'),
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
              controller: item.floorController,
              decoration: const InputDecoration(
                labelText: 'ชั้นที่ (ถ้ามี)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: item.roomController,
              decoration: const InputDecoration(
                labelText: 'เลขห้อง (ถ้ามี)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
}

class _LocationPickerDialog extends StatefulWidget {
  const _LocationPickerDialog({this.initialPosition});

  final LatLng? initialPosition;

  @override
  State<_LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<_LocationPickerDialog> {
  static const _campusCenter = LatLng(13.1205, 100.9190);
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
  final floorController = TextEditingController();
  final roomController = TextEditingController();
  final equipmentController = TextEditingController();
  final detailsController = TextEditingController();
  String? photoName;
  Uint8List? photoBytes;

  void dispose() {
    floorController.dispose();
    roomController.dispose();
    equipmentController.dispose();
    detailsController.dispose();
  }
}
