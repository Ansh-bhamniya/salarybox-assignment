import 'package:dio/dio.dart';
import '../../config/env.dart';
import './api_exception.dart';

/// Thin wrapper around [Dio]. Holds the current session token in memory and
/// attaches it to every outgoing request; [AuthService] is the only
/// caller that sets/clears it (on login, on app-start session restore, on
/// logout) so this class never has to know how the session is persisted.
class ApiClient {
  ApiClient() : dio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl)) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.reject(_mapError(error));
        },
      ),
    );
  }

  final Dio dio;
  String? _token;

  void setToken(String? token) => _token = token;

  DioException _mapError(DioException error) {
    final data = error.response?.data;
    final message = (data is Map && data['error'] is String)
        ? data['error'] as String
        : error.message ?? 'Network error';

    return DioException(
      requestOptions: error.requestOptions,
      response: error.response,
      type: error.type,
      error: ApiException(message, statusCode: error.response?.statusCode),
    );
  }
}

/// Runs a dio call and converts thrown [DioException]s into [ApiException]
/// so callers only ever need to catch one type.
Future<T> runApiCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    if (e.error is ApiException) throw e.error as ApiException;
    throw ApiException(e.message ?? 'Network error');
  }
}
