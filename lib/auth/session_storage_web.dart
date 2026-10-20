import 'package:web/web.dart' as web;
import 'session_storage.dart';

class WebSessionStorage implements BrowserSessionStorage {
  @override
  void save(String key, String value) {
    try {
      web.window.sessionStorage.setItem(key, value);
    } catch (_) {}
  }

  @override
  String? read(String key) {
    try {
      return web.window.sessionStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @override
  void remove(String key) {
    try {
      web.window.sessionStorage.removeItem(key);
    } catch (_) {}
  }
}

BrowserSessionStorage getSessionStorage() => WebSessionStorage();

