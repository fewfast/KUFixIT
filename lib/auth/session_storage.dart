import 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart';

abstract class BrowserSessionStorage {
  static BrowserSessionStorage get instance => getSessionStorage();

  void save(String key, String value);
  String? read(String key);
  void remove(String key);
}

