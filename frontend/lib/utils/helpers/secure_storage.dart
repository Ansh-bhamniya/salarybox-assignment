import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around [FlutterSecureStorage] scoped to the one thing this
/// app needs persisted across restarts: the session (token + role + staffId
/// packed as JSON by [AuthService]).
class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _sessionKey = 'session';

  Future<void> saveSession(String rawJson) => _storage.write(key: _sessionKey, value: rawJson);

  Future<String?> readSession() => _storage.read(key: _sessionKey);

  Future<void> clearSession() => _storage.delete(key: _sessionKey);
}
