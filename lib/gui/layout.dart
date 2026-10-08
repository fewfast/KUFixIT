import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/function_error_message.dart';
import '../auth/google_auth.dart';
import '../auth/temporary_account_session.dart';
import '../database/connect.dart';
import 'personal_info_page.dart';
import 'superRegister.dart';
import 'tickerMonitor.dart';

class Layout extends StatefulWidget {
  const Layout({super.key, this.roleOverride});

  final String? roleOverride;

  @override
  State<Layout> createState() => _LayoutState();
}

class _LayoutState extends State<Layout> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedPage;
  int _profileImageRevision = 0;
  bool _isRefreshingGoogleAccount = false;

  @override
  void initState() {
    super.initState();
    if (widget.roleOverride == null) _restoreGoogleSession();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.roleOverride case final role?) {
      return _buildShell(role, null);
    }

    return AnimatedBuilder(
      animation: TemporaryAccountSession.instance,
      builder: (context, _) {
        final account = TemporaryAccountSession.instance.account;
        return _buildShell(account?.role ?? 'Unsign', account);
      },
    );
  }

  Widget _buildShell(String role, TemporaryAccount? temporaryAccount) {
    final pages = _pagesFor(role);
    final selectedIndex = pages.indexWhere((page) => page.id == _selectedPage);
    final currentIndex = selectedIndex < 0 ? 0 : selectedIndex;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'เปิดเมนู',
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        centerTitle: true,
        title: const Text(
          'KUFixIT',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (temporaryAccount == null)
            IconButton(
              tooltip: 'เข้าสู่ระบบ',
              onPressed: () => _showLoginDialog(context),
              icon: const CircleAvatar(
                radius: 17,
                child: Icon(Icons.person_outline, size: 21),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'บัญชีผู้ใช้',
              onSelected: (value) {
                if (value == 'sign_out') {
                  _signOut(context);
                } else if (value == 'personal_info') {
                  _showPersonalInfoPage(context, temporaryAccount);
                } else if (value == 'register') {
                  _showRegisterPage(context);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(temporaryAccount.displayName),
                ),
                const PopupMenuDivider(),
                if (!temporaryAccount.isSystemAccount &&
                    (role == 'User' || role == 'Admin'))
                  const PopupMenuItem<String>(
                    value: 'personal_info',
                    child: Text('ข้อมูลส่วนตัว'),
                  )
                else if (!temporaryAccount.isSystemAccount)
                  const PopupMenuItem<String>(
                    value: 'register',
                    child: Text('สร้างบัญชีผู้ใช้'),
                  ),
                const PopupMenuItem<String>(
                  value: 'sign_out',
                  child: Text('ออกจากระบบ'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _avatar(temporaryAccount),
              ),
            ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KUFixIT',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (temporaryAccount != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        temporaryAccount.isSystemAccount
                            ? 'บัญชี: ${temporaryAccount.username}'
                            : 'UID: ${temporaryAccount.uid ?? '-'}',
                      ),
                    ],
                    if (role == 'User' || role == 'Admin') ...[
                      const SizedBox(height: 4),
                      Text('Role: $role'),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (var index = 0; index < pages.length; index++)
                      ListTile(
                        leading: Icon(pages[index].icon),
                        title: Text(pages[index].label),
                        selected: index == currentIndex,
                        onTap: () {
                          setState(() => _selectedPage = pages[index].id);
                          _scaffoldKey.currentState?.closeDrawer();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      onDrawerChanged: (isOpened) {
        final account = temporaryAccount;
        if (isOpened &&
            account != null &&
            !account.isSystemAccount &&
            account.uid == null) {
          _refreshGoogleAccount();
        }
      },
      body: IndexedStack(
        index: currentIndex,
        children: [
          for (final page in pages)
            if (page.id == 'ticket_monitor')
              const TickerMonitor()
            else
              _PageContent(page: page, role: role),
        ],
      ),
    );
  }

  Future<void> _refreshGoogleAccount() async {
    if (_isRefreshingGoogleAccount || !SupabaseConnection.isInitialized) return;
    final client = SupabaseConnection.client;
    if (!isGoogleUser(client.auth.currentUser)) return;

    _isRefreshingGoogleAccount = true;
    try {
      final response = await client.functions.invoke(
        'login-user',
        body: const <String, dynamic>{},
      );
      TemporaryAccountSession.instance.setFromResponse(response.data);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            functionErrorMessage(error, 'โหลดข้อมูล UID ไม่สำเร็จ'),
          ),
        ),
      );
    } finally {
      _isRefreshingGoogleAccount = false;
    }
  }

  Future<void> _showLoginDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _LoginDialog(
        onRegister: () {
          Navigator.pop(dialogContext);
          _showRegisterPage(context);
        },
      ),
    );
  }

  Future<void> _showRegisterPage(BuildContext context) async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const SuperRegisterPage()));
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('สร้างบัญชีเรียบร้อยแล้ว')));
    }
  }

  Future<void> _showPersonalInfoPage(
    BuildContext context,
    TemporaryAccount? temporaryAccount,
  ) async {
    if (temporaryAccount == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PersonalInfoPage(temporaryAccount: temporaryAccount),
      ),
    );
    if (mounted) {
      setState(() => _profileImageRevision++);
    }
  }

  Future<void> _restoreGoogleSession() async {
    if (!SupabaseConnection.isInitialized) return;
    final client = SupabaseConnection.client;
    if (!isGoogleUser(client.auth.currentUser)) return;

    try {
      final response = await client.functions.invoke(
        'login-user',
        body: const <String, dynamic>{},
      );
      TemporaryAccountSession.instance.setFromResponse(response.data);
    } on Exception catch (error) {
      if (!mounted) return;
      if (_isUnregisteredGoogleAccount(error)) {
        await _registerGoogleAccount(client);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              functionErrorMessage(error, 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _registerGoogleAccount(SupabaseClient client) async {
    try {
      final response = await client.functions.invoke(
        'register-user',
        body: const <String, dynamic>{},
      );
      TemporaryAccountSession.instance.setFromResponse(response.data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สมัครสมาชิกและเข้าสู่ระบบเรียบร้อยแล้ว')),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(functionErrorMessage(error, 'สร้างบัญชีไม่สำเร็จ')),
        ),
      );
    }
  }

  bool _isUnregisteredGoogleAccount(Object error) {
    if (error is! FunctionException || error.status != 404) return false;
    final details = error.details;
    return details is Map && details['code'] == 'google_account_not_registered';
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await SupabaseConnection.client.auth.signOut();
      TemporaryAccountSession.instance.clear();
    } on Exception catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ออกจากระบบไม่สำเร็จ: $error')));
    }
  }

  Widget _avatar(TemporaryAccount? temporaryAccount) {
    if (temporaryAccount?.isSystemAccount == true) {
      return const CircleAvatar(
        radius: 17,
        child: Icon(Icons.person_outline, size: 21),
      );
    }
    return _ProfileAvatar(
      key: ValueKey('${temporaryAccount?.id}:$_profileImageRevision'),
      accessToken: temporaryAccount?.accessToken,
    );
  }
}

class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({super.key, required this.accessToken});

  final String? accessToken;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  String? _avatarUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(covariant _ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessToken != widget.accessToken) _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final accessToken = widget.accessToken;
    if (accessToken == null || !SupabaseConnection.isInitialized) {
      setState(() {
        _avatarUrl = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'profile-avatar',
        headers: {
          'Authorization': 'Bearer $accessToken',
          'x-avatar-action': 'get',
        },
        body: const {'action': 'get'},
      );
      final data = response.data;
      final url = data is Map ? data['url'] : null;
      if (url != null && url is! String) {
        throw const FormatException('Invalid profile image response.');
      }
      if (mounted) {
        setState(() {
          _avatarUrl = url as String?;
          _isLoading = false;
        });
      }
    } on Exception catch (error) {
      debugPrint('Failed to load profile image for app bar: $error');
      if (mounted) {
        setState(() {
          _avatarUrl = null;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _avatarUrl;
    return CircleAvatar(
      radius: 18,
      backgroundImage: imageUrl == null ? null : NetworkImage(imageUrl),
      child: imageUrl == null || _isLoading
          ? const Icon(Icons.person_outline, size: 21)
          : null,
    );
  }
}

class _PageInfo {
  const _PageInfo(this.id, this.label, this.icon, this.description);

  final String id;
  final String label;
  final IconData icon;
  final String description;
}

List<_PageInfo> _pagesFor(String role) {
  final dashboard = const _PageInfo(
    'dashboard',
    'หน้าหลัก',
    Icons.dashboard_outlined,
    'ภาพรวมการใช้งานระบบ',
  );

  return switch (role) {
    'Technician' => [
      dashboard,
      const _PageInfo(
        'assigned',
        'งานที่ได้รับ',
        Icons.assignment_outlined,
        'รายการงานซ่อมที่ได้รับมอบหมาย',
      ),
      const _PageInfo(
        'history',
        'ประวัติการซ่อม',
        Icons.history,
        'ประวัติการดำเนินงานซ่อม',
      ),
    ],
    'Admin' => [
      dashboard,
      const _PageInfo(
        'requests',
        'คำร้องแจ้งซ่อม',
        Icons.home_repair_service_outlined,
        'จัดการคำร้องแจ้งซ่อมทั้งหมด',
      ),
      const _PageInfo(
        'users',
        'จัดการผู้ใช้',
        Icons.people_outline,
        'จัดการบัญชีและบทบาทผู้ใช้',
      ),
      const _PageInfo(
        'reports',
        'รายงาน',
        Icons.assessment_outlined,
        'รายงานภาพรวมการแจ้งซ่อม',
      ),
    ],
    'SuperAdmin' => [
      dashboard,
      const _PageInfo(
        'requests',
        'คำร้องแจ้งซ่อม',
        Icons.home_repair_service_outlined,
        'จัดการคำร้องแจ้งซ่อมทั้งหมด',
      ),
      const _PageInfo(
        'users',
        'จัดการผู้ใช้',
        Icons.people_outline,
        'จัดการบัญชีและบทบาทผู้ใช้',
      ),
      const _PageInfo(
        'reports',
        'รายงาน',
        Icons.assessment_outlined,
        'รายงานภาพรวมการแจ้งซ่อม',
      ),
      const _PageInfo(
        'settings',
        'ตั้งค่าระบบ',
        Icons.settings_outlined,
        'ตั้งค่าระบบ KUFixIT',
      ),
    ],
    'Unsign' => [
      const _PageInfo(
        'ticket_monitor',
        'ติดตามงานซ่อม',
        Icons.monitor_heart_outlined,
        'ติดตามสถานะงานซ่อม',
      ),
    ],
    _ => [
      dashboard,
      const _PageInfo(
        'new_request',
        'แจ้งซ่อม',
        Icons.add_circle_outline,
        'สร้างคำร้องแจ้งซ่อมใหม่',
      ),
      const _PageInfo(
        'my_requests',
        'รายการแจ้งซ่อมของฉัน',
        Icons.receipt_long_outlined,
        'ติดตามสถานะคำร้องแจ้งซ่อมของคุณ',
      ),
    ],
  };
}

class _PageContent extends StatelessWidget {
  const _PageContent({required this.page, required this.role});

  final _PageInfo page;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              page.icon,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              page.label,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(page.description, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('บทบาท: $role'),
          ],
        ),
      ),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.onRegister});

  final VoidCallback onRegister;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _isSubmitting = false;
  bool _isCompletingSignIn = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (SupabaseConnection.isInitialized) {
      _authSubscription = SupabaseConnection.client.auth.onAuthStateChange
          .listen((state) {
            if (state.event == AuthChangeEvent.signedIn &&
                isGoogleUser(state.session?.user)) {
              _completeGoogleSignIn();
            }
          });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เข้าสู่ระบบ'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('เข้าสู่ระบบด้วยบัญชี Google ของคุณ'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _signIn,
              icon: const Icon(Icons.login),
              label: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('เข้าสู่ระบบด้วย Google'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isSubmitting ? null : widget.onRegister,
                child: const Text('ยังไม่มีบัญชี? สมัครสมาชิก'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _showStaffLoginDialog,
              icon: const Icon(Icons.engineering_outlined),
              label: const Text('เข้าสู่ระบบช่างและเจ้าหน้าที่ระดับสูง'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
      ],
    );
  }

  Future<void> _showStaffLoginDialog() async {
    final signedIn = await showDialog<bool>(
      context: context,
      builder: (_) => const _StaffLoginDialog(),
    );
    if (signedIn == true && mounted) Navigator.pop(context);
  }

  Future<void> _signIn() async {
    if (!SupabaseConnection.isInitialized) {
      setState(() => _errorMessage = 'ยังไม่ได้เชื่อมต่อบริการเข้าสู่ระบบ');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await startGoogleSignIn();
    } on Exception catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = functionErrorMessage(
          error,
          'เข้าสู่ระบบด้วย Google ไม่สำเร็จ',
        ),
      );
    } finally {
      if (mounted && !_isCompletingSignIn) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _completeGoogleSignIn() async {
    if (_isCompletingSignIn || !mounted) return;
    _isCompletingSignIn = true;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'login-user',
        body: const <String, dynamic>{},
      );
      TemporaryAccountSession.instance.setFromResponse(response.data);
      if (mounted) Navigator.pop(context);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage = functionErrorMessage(error, 'เข้าสู่ระบบไม่สำเร็จ'),
      );
    } finally {
      _isCompletingSignIn = false;
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class _StaffLoginDialog extends StatefulWidget {
  const _StaffLoginDialog();

  @override
  State<_StaffLoginDialog> createState() => _StaffLoginDialogState();
}

class _StaffLoginDialogState extends State<_StaffLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เข้าสู่ระบบช่างและเจ้าหน้าที่ระดับสูง'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _usernameController,
                enabled: !_isSubmitting,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'ชื่อผู้ใช้'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'กรุณากรอกชื่อผู้ใช้'
                    : null,
              ),
              TextFormField(
                controller: _passwordController,
                enabled: !_isSubmitting,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _signIn(),
                decoration: const InputDecoration(labelText: 'รหัสผ่าน'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'กรุณากรอกรหัสผ่าน' : null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _signIn,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('เข้าสู่ระบบ'),
        ),
      ],
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    if (!SupabaseConnection.isInitialized) {
      setState(() => _errorMessage = 'ยังไม่ได้เชื่อมต่อบริการเข้าสู่ระบบ');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final response = await SupabaseConnection.client.functions.invoke(
        'staff-login',
        body: {
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
        },
      );
      TemporaryAccountSession.instance.setFromResponse(response.data);
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage = functionErrorMessage(error, 'เข้าสู่ระบบไม่สำเร็จ'),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
