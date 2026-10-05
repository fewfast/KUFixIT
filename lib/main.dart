import 'package:flutter/material.dart';
import 'database/connect.dart';
import 'gui/pageList.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConnection.initialize();
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
      home: const pageList(),
    );
  }
}
