import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConnection {
  SupabaseConnection._();

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static Future<void> initialize() async {
    if (_url.isEmpty || _anonKey.isEmpty) {
      throw StateError(
        'Set SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define.',
      );
    }

    await Supabase.initialize(url: _url, anonKey: _anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}