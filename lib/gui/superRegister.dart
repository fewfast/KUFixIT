import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/function_error_message.dart';
import '../auth/google_auth.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';

class SuperRegisterPage extends StatefulWidget {
  const SuperRegisterPage({super.key});

  @override
  State<SuperRegisterPage> createState() => _SuperRegisterPageState();
}

class _SuperRegisterPageState extends State<SuperRegisterPage> {
  StreamSubscription<AuthState>? _authSubscription;
  String? _googleEmail;
  String? _lastAttemptedUserId;
  bool _isLaunchingGoogle = false;
  bool _isSubmitting = false;
  bool _registrationInProgress = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (SupabaseConnection.isInitialized) {
      final client = SupabaseConnection.client;
      _authSubscription = client.auth.onAuthStateChange.listen(
        (state) => _handleGoogleUser(state.session?.user),
      );
      _handleGoogleUser(client.auth.currentUser);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _handleGoogleUser(User? user) {
    if (!isGoogleUser(user)) {
      if (_googleEmail != null && mounted) {
        setState(() => _googleEmail = null);
      }
      return;
    }

    final email = user!.email?.trim();
    if (email == null || email.isEmpty || !mounted) return;
    setState(() {
      _googleEmail = email;
      _errorMessage = null;
    });
    if (_lastAttemptedUserId != user.id) {
      _lastAttemptedUserId = user.id;
      unawaited(_createAccount());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGoogleAccount = _googleEmail != null;
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
                      if (!hasGoogleAccount) ...[
                        const Text(
                          'สมัครสมาชิกด้วยบัญชี Google '
                          'ระบบจะสร้างบัญชี KUFixIT หลังยืนยันตัวตนสำเร็จ',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isLaunchingGoogle
                              ? null
                              : _signInWithGoogle,
                          icon: const Icon(Icons.login),
                          label: _isLaunchingGoogle
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('สมัครด้วย Google'),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ] else ...[
                        Text(
                          'บัญชี Google: $_googleEmail',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (_isSubmitting)
                          const Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('กำลังสร้างบัญชี KUFixIT...'),
                            ],
                          )
                        else if (_errorMessage != null) ...[
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _registrationInProgress
                                ? null
                                : _retryRegistration,
                            child: const Text('ลองอีกครั้ง'),
                          ),
                          TextButton(
                            onPressed: _isLaunchingGoogle
                                ? null
                                : _signInWithGoogle,
                            child: const Text('เปลี่ยนบัญชี Google'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLaunchingGoogle = true;
      _errorMessage = null;
    });
    try {
      await startGoogleSignIn();
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = functionErrorMessage(
            error,
            'สมัครด้วย Google ไม่สำเร็จ',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLaunchingGoogle = false);
    }
  }

  Future<void> _retryRegistration() async {
    final user = SupabaseConnection.client.auth.currentUser;
    if (!isGoogleUser(user)) return;
    await _createAccount();
  }

  Future<void> _createAccount() async {
    if (_registrationInProgress || !mounted) return;
    _registrationInProgress = true;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'register-user',
        body: const <String, dynamic>{},
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
      _registrationInProgress = false;
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
