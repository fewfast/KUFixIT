import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/connect.dart';
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

  @override
  Widget build(BuildContext context) {
    if (widget.roleOverride case final role?) {
      return _buildShell(role, null);
    }

    return StreamBuilder<AuthState>(
      stream: SupabaseConnection.client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        SupabaseConnection.client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final user = snapshot.data?.session?.user;
        return _buildShell(_roleFor(user), user);
      },
    );
  }

  Widget _buildShell(String role, User? user) {
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
          if (user == null)
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
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(_displayName(user)),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'sign_out',
                  child: Text('ออกจากระบบ'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _avatar(user),
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
                    const SizedBox(height: 8),
                    Text('บทบาท: $role'),
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

  Future<void> _showLoginDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const _LoginDialog(),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await SupabaseConnection.client.auth.signOut();
    } on Exception catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ออกจากระบบไม่สำเร็จ: $error')));
    }
  }

  String _roleFor(User? user) {
    if (user == null) return 'Unsign';

    final rawRole = user.appMetadata['role'] ?? user.userMetadata?['role'];
    final normalizedRole = rawRole?.toString().toLowerCase();
    return switch (normalizedRole) {
      'technician' => 'Technician',
      'admin' => 'Admin',
      'superadmin' => 'SuperAdmin',
      _ => 'User',
    };
  }

  String _displayName(User user) {
    final name = user.userMetadata?['full_name'] ?? user.userMetadata?['name'];
    if (name is String && name.isNotEmpty) return name;
    return user.email ?? 'บัญชีผู้ใช้';
  }

  Widget _avatar(User user) {
    final avatarUrl = user.userMetadata?['avatar_url'];
    if (avatarUrl is String && avatarUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const CircleAvatar(child: Icon(Icons.person_outline)),
        ),
      );
    }
    return const CircleAvatar(
      radius: 18,
      child: Icon(Icons.person_outline, size: 21),
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
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เข้าสู่ระบบ'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'อีเมล'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'กรุณากรอกอีเมล'
                    : null,
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
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
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
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
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await SupabaseConnection.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) Navigator.pop(context);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เข้าสู่ระบบไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
