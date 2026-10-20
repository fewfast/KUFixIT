import 'session_storage.dart';

class StubSessionStorage implements BrowserSessionStorage {
  final Map<String, String> _memory = {};

  @override
  void save(String key, String value) {
    _memory[key] = value;
  }

  @override
  String? read(String key) {
    return _memory[key];
  }

  @override
  void remove(String key) {
    _memory.remove(key);
  }
}

BrowserSessionStorage getSessionStorage() => StubSessionStorage();

