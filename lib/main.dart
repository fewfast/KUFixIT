import 'package:flutter/material.dart';

import 'database/connect.dart';
import 'gui/layout.dart';
import 'gui/database_connection_error_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KUFixITApp());
}

class KUFixITApp extends StatelessWidget {
  const KUFixITApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KUFixIT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _ConnectionGate(),
    );
  }
}

class _ConnectionGate extends StatefulWidget {
  const _ConnectionGate();

  @override
  State<_ConnectionGate> createState() => _ConnectionGateState();
}

class _ConnectionGateState extends State<_ConnectionGate> {
  bool _isChecking = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    try {
      await SupabaseConnection.checkConnection().timeout(
        const Duration(seconds: 15),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('กำลังเชื่อมต่อฐานข้อมูล...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage case final error?) {
      return DatabaseConnectionErrorPage(
        errorMessage: error,
        onRetry: _checkConnection,
        isRetrying: _isChecking,
      );
    }

    return const Layout();
  }
}
