import 'package:flutter/material.dart';

class DatabaseConnectionErrorPage extends StatelessWidget {
  const DatabaseConnectionErrorPage({required this.errorMessage, super.key});

  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('เชื่อมต่อฐานข้อมูลไม่ได้')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 64,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'ไม่สามารถเชื่อมต่อ Supabase ได้',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.error),
                ),
                const SizedBox(height: 24),
                const Text('ระบบจะลองเชื่อมต่อใหม่โดยอัตโนมัติ'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
