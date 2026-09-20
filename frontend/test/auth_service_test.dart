import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/session.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/utils/helpers/secure_storage.dart';
import 'package:frontend/utils/http/api_client.dart';
import 'package:frontend/utils/http/api_exception.dart';
import 'helpers/fake_http_adapter.dart';

/// Keeps the session in memory instead of the device keychain.
class _MemoryStorage extends SecureStorage {
  _MemoryStorage() : super(const FlutterSecureStorage());

  String? raw;

  @override
  Future<void> saveSession(String rawJson) async => raw = rawJson;

  @override
  Future<String?> readSession() async => raw;

  @override
  Future<void> clearSession() async => raw = null;
}

void main() {
  late FakeHttpAdapter adapter;
  late ApiClient client;
  late _MemoryStorage storage;
  late AuthService service;

  setUp(() {
    adapter = FakeHttpAdapter();
    client = ApiClient()..dio.httpClientAdapter = adapter;
    storage = _MemoryStorage();
    service = AuthService(client, storage);
  });

  /// Header the client would attach to the *next* request.
  Future<String?> authHeaderNow() async {
    await client.dio.get('/ping');
    return adapter.request.headers['Authorization'] as String?;
  }

  test('a staff login posts the credentials and returns the staff session', () async {
    adapter.body = '{"token":"tok","role":"staff","staff":{"id":"s1","employeeId":"E-7","name":"Sam Rao"}}';

    final session = await service.login(username: 'E-7', password: 'staff123');

    expect(adapter.requests.single.path, '/auth/login');
    expect(adapter.requests.single.data, {'username': 'E-7', 'password': 'staff123'});
    expect(session.role, UserRole.staff);
    expect(session.staffId, 's1');
    expect(session.staffName, 'Sam Rao');
    expect(session.employeeId, 'E-7');
  });

  test('an admin login has no staff details', () async {
    adapter.body = '{"token":"tok","role":"admin"}';

    final session = await service.login(username: 'admin', password: 'admin123');

    expect(session.role, UserRole.admin);
    expect(session.staffId, isNull);
  });

  test('login attaches the token to later requests and saves the session on the device', () async {
    adapter.body = '{"token":"tok","role":"admin"}';
    await service.login(username: 'admin', password: 'admin123');

    expect(storage.raw, isNotNull);
    expect(Session.decode(storage.raw!).token, 'tok');

    expect(await authHeaderNow(), 'Bearer tok');
  });

  test('a rejected login surfaces the backend message and stores nothing', () async {
    adapter
      ..status = 401
      ..body = '{"error":"Invalid credentials"}';

    await expectLater(
      service.login(username: 'admin', password: 'wrong'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid credentials')),
    );
    expect(storage.raw, isNull);
  });

  test('restoreSession is null when nothing was saved', () async {
    expect(await service.restoreSession(), isNull);
  });

  test('restoreSession brings back the saved session and re-attaches its token', () async {
    storage.raw = const Session(token: 'saved', role: UserRole.admin).encode();

    final session = await service.restoreSession();

    expect(session!.token, 'saved');
    expect(await authHeaderNow(), 'Bearer saved');
  });

  test('logout forgets the session and stops sending the token', () async {
    adapter.body = '{"token":"tok","role":"admin"}';
    await service.login(username: 'admin', password: 'admin123');

    await service.logout();

    expect(storage.raw, isNull);
    expect(await authHeaderNow(), isNull);
  });
}
