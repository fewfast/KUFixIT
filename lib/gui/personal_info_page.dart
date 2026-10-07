import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../auth/account_identity.dart';
import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key, required this.temporaryAccount});

  final TemporaryAccount? temporaryAccount;

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  static const _maxAvatarSizeBytes = 5 * 1024 * 1024;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _nationalIdController;
  late final TextEditingController _newPasswordController;
  late final TextEditingController _confirmPasswordController;
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  bool _isSubmitting = false;
  bool _isEditing = false;
  bool _isLoadingAvatar = true;
  bool _isUploadingAvatar = false;
  late String _savedFirstName;
  late String _savedLastName;
  late String _savedUsername;
  String? _avatarUrl;
  String? _avatarErrorMessage;
  String? _errorMessage;

  bool get _requiresNationalId =>
      _newPasswordController.text.isNotEmpty ||
      _usernameController.text.trim().toLowerCase() !=
          _savedUsername.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    final account = widget.temporaryAccount;
    _firstNameController = TextEditingController(
      text: account?.firstName ?? '',
    );
    _lastNameController = TextEditingController(text: account?.lastName ?? '');
    _usernameController = TextEditingController(text: account?.username ?? '');
    _nationalIdController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _saveCurrentValues();
    if (SupabaseConnection.isInitialized) {
      _loadAvatar();
    } else {
      _isLoadingAvatar = false;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _nationalIdController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.temporaryAccount;
    final role = account?.role ?? 'User';
    final uid = account?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('ข้อมูลส่วนตัว')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'รูปโปรไฟล์',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: InkWell(
                            onTap:
                                _isUploadingAvatar ||
                                    _isLoadingAvatar ||
                                    !_isEditing
                                ? null
                                : _chooseAvatar,
                            customBorder: const CircleBorder(),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 60,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  child: _avatarUrl == null
                                      ? Icon(
                                          Icons.person_outline,
                                          size: 64,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        )
                                      : ClipOval(
                                          child: Image.network(
                                            _avatarUrl!,
                                            key: ValueKey(_avatarUrl),
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stack) =>
                                                    const Icon(
                                                      Icons.person_outline,
                                                      size: 64,
                                                    ),
                                          ),
                                        ),
                                ),
                                if (_isLoadingAvatar || _isUploadingAvatar)
                                  const Positioned.fill(
                                    child: CircleAvatar(
                                      backgroundColor: Color(0x66000000),
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                if (_isEditing)
                                  const Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: CircleAvatar(
                                      radius: 18,
                                      child: Icon(Icons.camera_alt_outlined),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isEditing
                              ? 'แตะรูปเพื่อเปลี่ยนรูปโปรไฟล์ (ไม่เกิน 5 MB)'
                              : 'รูปโปรไฟล์ปัจจุบัน',
                          textAlign: TextAlign.center,
                        ),
                        if (_avatarErrorMessage case final error?) ...[
                          const SizedBox(height: 8),
                          Text(
                            error,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (_isEditing) ...[
                          _characterCount(_firstNameController, 80),
                          TextFormField(
                            controller: _firstNameController,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 80,
                            buildCounter: _hideCharacterCounter,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'ชื่อจริง',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                _validateName(value, 'ชื่อจริง'),
                          ),
                          const SizedBox(height: 16),
                          _characterCount(_lastNameController, 80),
                          TextFormField(
                            controller: _lastNameController,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 80,
                            buildCounter: _hideCharacterCounter,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'นามสกุล',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                _validateName(value, 'นามสกุล'),
                          ),
                          const SizedBox(height: 16),
                          _characterCount(_usernameController, 30),
                          TextFormField(
                            controller: _usernameController,
                            autocorrect: false,
                            enableSuggestions: false,
                            maxLength: 30,
                            buildCounter: _hideCharacterCounter,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'ชื่อบัญชี',
                              helperText: 'ใช้ a-z, 0-9, _ หรือ - (3-30 ตัว)',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateUsername,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _newPasswordController,
                            obscureText: true,
                            maxLength: 128,
                            buildCounter: _hideCharacterCounter,
                            onChanged: (value) {
                              if (value.isEmpty) {
                                _confirmPasswordController.clear();
                                if (_usernameController.text
                                        .trim()
                                        .toLowerCase() ==
                                    _savedUsername.trim().toLowerCase()) {
                                  _nationalIdController.clear();
                                }
                              }
                              setState(() {});
                            },
                            decoration: const InputDecoration(
                              labelText: 'รหัสผ่านใหม่ (เว้นว่างถ้าไม่เปลี่ยน)',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateNewPassword,
                          ),
                          if (_newPasswordController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildPasswordChecklist(context),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              maxLength: 128,
                              buildCounter: _hideCharacterCounter,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'ยืนยันรหัสผ่านใหม่',
                                border: OutlineInputBorder(),
                              ),
                              validator: _validateConfirmPassword,
                            ),
                          ],
                          if (_requiresNationalId) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nationalIdController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              maxLength: 13,
                              buildCounter: _hideCharacterCounter,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'เลขบัตรประชาชนเพื่อยืนยัน',
                                helperText:
                                    'กรอกตัวเลข 13 หลักเดียวกับตอนสมัครเพื่อเปลี่ยน Username หรือรหัสผ่าน',
                                border: OutlineInputBorder(),
                              ),
                              validator: _validateNationalId,
                            ),
                          ],
                        ] else ...[
                          _InformationRow(
                            label: 'ชื่อจริง',
                            value: _displayValue(_firstNameController.text),
                          ),
                          const SizedBox(height: 12),
                          _InformationRow(
                            label: 'นามสกุล',
                            value: _displayValue(_lastNameController.text),
                          ),
                          const SizedBox(height: 12),
                          _InformationRow(
                            label: 'ชื่อบัญชี',
                            value: _displayValue(_usernameController.text),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _InformationRow(label: 'บทบาท', value: role),
                        const SizedBox(height: 12),
                        _InformationRow(label: 'เลขบัญชี', value: uid),
                        if (_errorMessage case final error?) ...[
                          const SizedBox(height: 12),
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (_isEditing)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSubmitting
                                      ? null
                                      : _cancelEditing,
                                  child: const Text('ยกเลิก'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _isSubmitting ? null : _save,
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('บันทึกข้อมูล'),
                                ),
                              ),
                            ],
                          )
                        else
                          FilledButton(
                            onPressed: () => setState(() {
                              _isEditing = true;
                              _errorMessage = null;
                              _avatarErrorMessage = null;
                            }),
                            child: const Text('แก้ไขข้อมูล'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateName(String? value, String label) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'กรุณากรอก$label';
    if (name.length > 80) return '$labelต้องมีความยาวไม่เกิน 80 ตัวอักษร';
    return null;
  }

  void _saveCurrentValues() {
    _savedFirstName = _firstNameController.text;
    _savedLastName = _lastNameController.text;
    _savedUsername = _usernameController.text;
  }

  void _cancelEditing() {
    _formKey.currentState?.reset();
    _firstNameController.text = _savedFirstName;
    _lastNameController.text = _savedLastName;
    _usernameController.text = _savedUsername;
    _clearSensitiveInputs();
    setState(() {
      _isEditing = false;
      _errorMessage = null;
      _avatarErrorMessage = null;
    });
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{3,30}$').hasMatch(username)) {
      return 'ชื่อบัญชีต้องมี 3-30 ตัว และใช้ได้เฉพาะ a-z, 0-9, _ หรือ -';
    }
    return null;
  }

  Widget? _hideCharacterCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) {
    return null;
  }

  Widget _buildPasswordChecklist(BuildContext context) {
    final checks = passwordRequirementStatus(
      _newPasswordController.text,
    ).entries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ตรวจสอบรหัสผ่าน', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              check.key == 'อักขระอย่างน้อย 8 ตัว'
                  ? '${check.key} (${_newPasswordController.text.length}/128)'
                  : check.key,
              style: TextStyle(
                color: check.value
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _characterCount(TextEditingController controller, int maxLength) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        '${controller.text.length}/$maxLength',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  String? _validateNationalId(String? value) {
    if (!_requiresNationalId) return null;
    final nationalId = value ?? '';
    if (nationalId.isEmpty) return 'กรุณากรอกเลขบัตรประชาชน';
    if (!RegExp(r'^\d{13}$').hasMatch(nationalId)) {
      return 'กรุณากรอกตัวเลข 13 หลัก';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return null;
    if (!isStrongPassword(password)) {
      return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัว และมีตัวพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และอักษรพิเศษ';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final password = _newPasswordController.text;
    if (password.isEmpty && (value ?? '').isEmpty) return null;
    if ((value ?? '') != password) return 'รหัสผ่านใหม่ไม่ตรงกัน';
    return null;
  }

  void _clearSensitiveInputs() {
    _nationalIdController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  Future<void> _loadAvatar() async {
    setState(() {
      _isLoadingAvatar = true;
      _avatarErrorMessage = null;
    });
    try {
      final response = await _callAvatarFunction(action: 'get');
      final data = _responseMap(response.body);
      final url = data['url'];
      if (url != null && url is! String) {
        throw const FormatException('Invalid profile image response.');
      }
      if (mounted) setState(() => _avatarUrl = url as String?);
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _avatarErrorMessage =
              'โหลดรูปโปรไฟล์ไม่สำเร็จ: ${_errorFromResponse(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAvatar = false);
    }
  }

  Future<void> _chooseAvatar() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final fileSize = await image.length();
      if (fileSize > _maxAvatarSizeBytes) {
        setState(
          () => _avatarErrorMessage = 'รูปโปรไฟล์ต้องมีขนาดไม่เกิน 5 MB',
        );
        return;
      }

      final mimeType = _imageMimeType(image);
      if (mimeType == null) {
        setState(
          () => _avatarErrorMessage =
              'กรุณาเลือกไฟล์รูปภาพ PNG, JPG, WEBP หรือ GIF',
        );
        return;
      }

      setState(() {
        _isUploadingAvatar = true;
        _avatarErrorMessage = null;
      });
      final bytes = await image.readAsBytes();
      if (bytes.length > _maxAvatarSizeBytes) {
        throw const FormatException('รูปโปรไฟล์ต้องมีขนาดไม่เกิน 5 MB');
      }
      final response = await _callAvatarFunction(
        action: 'upload',
        body: bytes,
        contentType: mimeType,
      );
      final data = _responseMap(response.body);
      final url = data['url'];
      if (url is! String) {
        throw const FormatException('ไม่ได้รับ URL ของรูปโปรไฟล์ที่อัปโหลด');
      }
      if (mounted) setState(() => _avatarUrl = url);
    } on Exception catch (error) {
      if (mounted)
        setState(() => _avatarErrorMessage = _errorFromResponse(error));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<http.Response> _callAvatarFunction({
    required String action,
    List<int>? body,
    String? contentType,
  }) async {
    final client = SupabaseConnection.client;
    final account = widget.temporaryAccount;
    final accessToken =
        account?.accessToken ?? client.auth.currentSession?.accessToken;
    if (accessToken == null) {
      throw const FormatException('กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง');
    }
    final headers = <String, String>{
      'Authorization': 'Bearer $accessToken',
      'apikey': SupabaseConnection.anonKey,
      'x-avatar-action': action,
      if (contentType != null) 'Content-Type': contentType,
      if (body == null) 'Content-Type': 'application/json',
    };
    final response = await http
        .post(
          Uri.parse('${SupabaseConnection.url}/functions/v1/profile-avatar'),
          headers: headers,
          body: body ?? jsonEncode({'action': action}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _ProfileAvatarException(_responseError(response.body));
    }
    return response;
  }

  Map<String, dynamic> _responseMap(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid profile image response.');
    }
    return decoded;
  }

  String _responseError(String responseBody) {
    try {
      final decoded = _responseMap(responseBody);
      final message = decoded['error'];
      if (message is String) return message;
    } on FormatException {
      return 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์';
    }
    return 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์';
  }

  String _errorFromResponse(Exception error) {
    if (error is _ProfileAvatarException) return error.message;
    if (error is FormatException) return error.message;
    return 'ไม่สามารถเชื่อมต่อบริการรูปโปรไฟล์ได้';
  }

  String? _imageMimeType(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (const {
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
    }.contains(mimeType)) {
      return mimeType;
    }
    final extension = file.name.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => null,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    final nationalId = _nationalIdController.text;
    final newPassword = _newPasswordController.text;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final account = widget.temporaryAccount;
      if (account == null) {
        throw const FormatException(
          'บัญชีนี้ไม่มีเลขบัตรที่ลงทะเบียนไว้ กรุณาสมัครบัญชีใหม่',
        );
      }

      await SupabaseConnection.client.functions.invoke(
        'update-user-profile',
        headers: {'Authorization': 'Bearer ${account.accessToken}'},
        body: {
          'firstName': firstName,
          'lastName': lastName,
          'username': username,
          'nationalId': nationalId,
          'newPassword': newPassword.isEmpty ? null : newPassword,
        },
      );
      TemporaryAccountSession.instance.updateProfile(
        firstName: firstName,
        lastName: lastName,
        username: username,
      );

      if (mounted) {
        setState(() {
          _saveCurrentValues();
          _clearSensitiveInputs();
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newPassword.isEmpty
                  ? 'บันทึกข้อมูลเรียบร้อยแล้ว'
                  : 'บันทึกข้อมูลและเปลี่ยนรหัสผ่านเรียบร้อยแล้ว',
            ),
          ),
        );
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = functionErrorMessage(
          error,
          'บันทึกข้อมูลส่วนตัวไม่สำเร็จ',
        ),
      );
    } finally {
      _clearSensitiveInputs();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  static String _displayValue(String value) {
    final trimmedValue = value.trim();
    return trimmedValue.isEmpty ? 'ยังไม่ได้ระบุ' : trimmedValue;
  }
}

class _ProfileAvatarException implements Exception {
  const _ProfileAvatarException(this.message);

  final String message;
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}
