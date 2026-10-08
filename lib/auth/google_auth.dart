import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/connect.dart';

const googleOAuthRedirectUrl = 'io.supabase.flutter://login-callback/';

bool isGoogleUser(User? user) {
  if (user == null) return false;
  return user.appMetadata['provider'] == 'google' ||
      (user.identities?.any((identity) => identity.provider == 'google') ??
          false);
}

Future<void> startGoogleSignIn() async {
  final launched = await SupabaseConnection.client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: kIsWeb ? Uri.base.origin : googleOAuthRedirectUrl,
    queryParams: const {'prompt': 'select_account'},
  );
  if (!launched) {
    throw const FormatException('ไม่สามารถเปิดหน้าลงชื่อเข้าใช้ Google ได้');
  }
}
