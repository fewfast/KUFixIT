import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConnection {
  SupabaseConnection._();

  static String get _url => dotenv.env['SUPABASE_URL'] ?? '';
  static String get _anonKey =>
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ??
      dotenv.env['SUPABASE_ANON_KEY'] ??
      '';
  static String get url => _url;
  static String get anonKey => _anonKey;
  static bool _isEnvironmentLoaded = false;
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    if (!_isEnvironmentLoaded) {
      await dotenv.load(fileName: '.env');
      _isEnvironmentLoaded = true;
    }

    if (_url.isEmpty || _anonKey.isEmpty) {
      throw Exception('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in .env.');
    }

    if (_isInitialized) return;

    await Supabase.initialize(url: _url, publishableKey: _anonKey);
    _isInitialized = true;
  }

  static Future<void> checkConnection() async {
    await initialize();

    final endpoint = Uri.parse(_url).resolve('/auth/v1/health');
    final response = await http
        .get(endpoint, headers: {'apikey': _anonKey})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Supabase Auth health check returned HTTP ${response.statusCode}.',
      );
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}
