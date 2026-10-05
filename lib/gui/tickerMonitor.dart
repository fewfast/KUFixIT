import 'package:flutter/material.dart';

class TickerMonitor extends StatelessWidget {
  const TickerMonitor({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'ติดตามงานซ่อม',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'สถานะงานซ่อมจะแสดงที่นี่เมื่อเชื่อมต่อข้อมูลแล้ว',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
