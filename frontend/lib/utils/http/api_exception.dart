/// One exception type for every backend failure, so repositories don't need
/// to know which endpoint produced it. [message] is either the backend's
/// `{ error: message }` body or a generic message for network-level
/// failures (timeouts, no connection). [code] and [details] carry the
/// backend's optional machine-readable reason and extra data (for example
/// `duplicate_face` with the staff it matched).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code, this.details});

  final String message;
  final int? statusCode;
  final String? code;
  final Object? details;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
