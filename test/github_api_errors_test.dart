import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/errors/app_failure.dart';
import 'package:winpilot/data/services/github_api.dart';

/// Answers requests from a function, so the HTTP status logic runs without a network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, String body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...?headers,
    });

GitHubApi _api({
  required Future<ResponseBody> Function(RequestOptions) github,
  Future<ResponseBody> Function(RequestOptions)? external,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
    ..httpClientAdapter = _FakeAdapter(github);
  final ext = Dio()
    ..httpClientAdapter = _FakeAdapter(external ?? (o) async => throw UnimplementedError(o.uri.toString()));
  return GitHubApi(tokenReader: () => 'test-token', dio: dio, externalDio: ext);
}

Future<FailureKind> _kindOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on AppFailure catch (e) {
    return e.kind;
  }
  fail('expected an AppFailure');
}

void main() {
  group('GitHub API status mapping (unit, no network)', () {
    test('listJobs 404 is notFound, not a connection problem', () async {
      final api = _api(github: (_) async => _json(404, '{"message":"Not Found"}'));
      expect(await _kindOf(() => api.listJobs('o', 'r', 1)), FailureKind.notFound);
    });

    test('listJobs 401 is unauthorized and 403 is forbidden', () async {
      final a = _api(github: (_) async => _json(401, '{"message":"Bad credentials"}'));
      expect(await _kindOf(() => a.listJobs('o', 'r', 1)), FailureKind.unauthorized);
      final b = _api(github: (_) async => _json(403, '{"message":"Resource not accessible"}'));
      expect(await _kindOf(() => b.listJobs('o', 'r', 1)), FailureKind.forbidden);
    });

    test('job logs not published yet (404) is notFound', () async {
      final api = _api(github: (_) async => _json(404, '{"message":"Not Found"}'));
      expect(await _kindOf(() => api.jobLogs('o', 'r', 9)), FailureKind.notFound);
    });

    test('expired log link (redirect then 404 from storage) is notFound, not network', () async {
      final api = _api(
        github: (_) async => _json(302, '', headers: {
          'location': ['https://pipelines.example.invalid/log?sig=x'],
        }),
        external: (_) async => _json(404, '<Error>expired</Error>'),
      );
      expect(await _kindOf(() => api.jobLogs('o', 'r', 9)), FailureKind.notFound);
    });

    test('a real transport failure is still reported as network', () async {
      final api = _api(
        github: (_) async => _json(302, '', headers: {
          'location': ['https://pipelines.example.invalid/log?sig=x'],
        }),
        external: (o) async => throw DioException.connectionError(
          requestOptions: o,
          reason: 'offline',
        ),
      );
      expect(await _kindOf(() => api.jobLogs('o', 'r', 9)), FailureKind.network);
    });

    test('a redirected log is returned as text', () async {
      final api = _api(
        github: (_) async => _json(302, '', headers: {
          'location': ['https://pipelines.example.invalid/log?sig=x'],
        }),
        external: (_) async => _json(200, 'line one\nWINPILOT|STAGE=session'),
      );
      expect(await api.jobLogs('o', 'r', 9), contains('WINPILOT|STAGE=session'));
    });
  });
}
