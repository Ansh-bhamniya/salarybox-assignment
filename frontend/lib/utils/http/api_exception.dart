/// One exception type for every backend failure, so repositories don't need
/// to know which endpoint produced it. [message] is either the backend's
/// `{ error: message }` body or a generic message for network-level
/// failures (timeouts, no connection).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
