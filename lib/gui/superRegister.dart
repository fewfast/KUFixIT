import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/account_identity.dart';
import '../auth/function_error_message.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';

class SuperRegisterPage extends StatefulWidget {
  const SuperRegisterPage({super.key});

  @override
  State<SuperRegisterPage> createState() => _SuperRegisterPageState();
}

class _SuperRegisterPageState extends State<SuperRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  String _role = 'User';
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nationalIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สร้างบัญชีผู้ใช้')),
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
                        Icon(
                          Icons.person_add_alt_1,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'สมัครสมาชิก KUFixIT',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _firstNameController,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.givenName],
                          maxLength: 80,
                          buildCounter: _hideCharacterCounter,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'ชื่อจริง',
                            border: OutlineInputBorder(),
                          ),
                          validator: _requiredValidator('กรุณากรอกชื่อจริง'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _lastNameController,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.familyName],
                          maxLength: 80,
                          buildCounter: _hideCharacterCounter,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'นามสกุล',
                            border: OutlineInputBorder(),
                          ),
                          validator: _requiredValidator('กรุณากรอกนามสกุล'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nationalIdController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          maxLength: 13,
                          buildCounter: _hideCharacterCounter,
                          decoration: const InputDecoration(
                            labelText: 'เลขบัตรประชาชน',
                            helperText:
                                'ตัวเลข 13 หลัก ใช้ตรวจสอบก่อนเปลี่ยนข้อมูลสำคัญ และห้ามซ้ำกับบัญชีอื่น',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final nationalId = value ?? '';
                            if (nationalId.isEmpty) {
                              return 'กรุณากรอกเลขบัตรประชาชน';
                            }
                            if (!RegExp(r'^\d{13}$').hasMatch(nationalId)) {
                              return 'กรุณากรอกตัวเลข 13 หลัก';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _usernameController,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 30,
                          buildCounter: _hideCharacterCounter,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            helperText:
                                'ใช้ตัวอักษรอังกฤษ ตัวเลข _ หรือ - (3-30 ตัว)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final username = value?.trim() ?? '';
                            if (username.isEmpty) return 'กรุณากรอก Username';
                            if (username.length < 3 || username.length > 30) {
                              return 'Username ต้องมีความยาว 3-30 ตัว';
                            }
                            if (!RegExp(
                              r'^[a-zA-Z0-9_-]+$',
                            ).hasMatch(username)) {
                              return 'Username ใช้ได้เฉพาะ a-z, 0-9, _ หรือ -';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          maxLength: 128,
                          buildCounter: _hideCharacterCounter,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'รหัสผ่าน',
                            helperText:
                                'อย่างน้อย 8 ตัว มีตัวพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และอักษรพิเศษ',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'แสดงรหัสผ่าน'
                                  : 'ซ่อนรหัสผ่าน',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกรหัสผ่าน';
                            }
                            final missingRequirements =
                                passwordRequirementStatus(value).entries
                                    .where((requirement) => !requirement.value)
                                    .map((requirement) => requirement.key)
                                    .toList();
                            if (missingRequirements.isNotEmpty) {
                              return 'รหัสผ่านยังขาด: ${missingRequirements.join(', ')}';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildRegistrationChecklist(context),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _role,
                          decoration: const InputDecoration(
                            labelText: 'บทบาท',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'User',
                              child: Text('User'),
                            ),
                            DropdownMenuItem(
                              value: 'Admin',
                              child: Text('Admin'),
                            ),
                            DropdownMenuItem(
                              value: 'SuperAdmin',
                              child: Text('SuperAdmin'),
                            ),
                          ],
                          onChanged: _isSubmitting
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _role = value);
                                  }
                                },
                        ),
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
                        FilledButton(
                          onPressed: _isSubmitting ? null : _createAccount,
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('สร้างบัญชี'),
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

  String? Function(String?) _requiredValidator(String message) {
    return (value) => value == null || value.trim().isEmpty ? message : null;
  }

  Widget _buildRegistrationChecklist(BuildContext context) {
    final passwordChecks = passwordRequirementStatus(_passwordController.text);
    final checks = <({String label, bool isMet})>[
      ...passwordChecks.entries.map(
        (entry) => (label: entry.key, isMet: entry.value),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ตรวจสอบรหัสผ่าน', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              check.label,
              style: TextStyle(
                color: check.isMet
                    ? Colors.green.shade700
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget? _hideCharacterCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) {
    return null;
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'register-user',
        body: {
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'nationalId': _nationalIdController.text,
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
          'role': _role,
        },
      );
      TemporaryAccountSession.instance.setFromResponse(response.data);

      if (mounted) Navigator.pop(context, true);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage = functionErrorMessage(error, 'สร้างบัญชีไม่สำเร็จ'),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
