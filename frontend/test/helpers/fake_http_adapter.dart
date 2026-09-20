import 'dart:typed_data';
import 'package:dio/dio.dart';

/// Stands in for the network in service tests: records every request and
/// replies with whatever status/body the test set.
class FakeHttpAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  String body = '{}';

  RequestOptions get request => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
