import 'package:flutter/material.dart';

class TechnicianManagerPage extends StatelessWidget {
  const TechnicianManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.engineering_outlined,
              size: 56,
              color: colors.primary,
            ),
            const SizedBox(height: 16),
            Text('จัดการช่างเทคนิค', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'จัดการบัญชีและข้อมูลช่างเทคนิค',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
