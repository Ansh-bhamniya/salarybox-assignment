import '../models/session.dart';
import '../utils/helpers/secure_storage.dart';
import '../utils/http/api_client.dart';

/// Everything about being signed in, in one place: logging in against the
/// backend, keeping the session on the device, restoring it at launch and
/// logging out.
class AuthService {
  AuthService(this._client, this._secureStorage);

  final ApiClient _client;
  final SecureStorage _secureStorage;

  /// Called once at app start to restore a previous session, if any, so the
  /// user doesn't have to log in again on every launch.
  Future<Session?> restoreSession() async {
    final raw = await _secureStorage.readSession();
    if (raw == null) return null;

    final session = Session.decode(raw);
    _client.setToken(session.token);
    return session;
  }

  Future<Session> login({required String username, required String password}) async {
    final json = await runApiCall(() async {
      final response = await _client.dio.post(
        '/auth/login',
        data: {'username': username, 'password': password},
      );
      return response.data as Map<String, dynamic>;
    });

    final role = UserRole.values.byName(json['role'] as String);
    final staff = json['staff'] as Map<String, dynamic>?;

    final session = Session(
      token: json['token'] as String,
      role: role,
      staffId: staff?['id'] as String?,
      staffName: staff?['name'] as String?,
      employeeId: staff?['employeeId'] as String?,
    );

    _client.setToken(session.token);
    await _secureStorage.saveSession(session.encode());
    return session;
  }

  Future<void> logout() async {
    _client.setToken(null);
    await _secureStorage.clearSession();
  }
}
