import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/security/redactor.dart';
import '../../models/github_models.dart';

typedef TokenReader = String? Function();

/// Thin, typed wrapper around the GitHub REST API.
///
/// Every failure is converted to [AppFailure] (no raw Dio exceptions leak out),
/// rate-limit headers are honoured, and 401 triggers [onUnauthorized] so the
/// session can be marked as expired.
class GitHubApi {
  GitHubApi({
    required TokenReader tokenReader,
    this.onUnauthorized,
    Dio? dio,
    Dio? externalDio,
  })  : _tokenReader = tokenReader,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.githubApiBase,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
            )),
        _external = externalDio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 3),
              headers: {'User-Agent': AppConfig.userAgent},
            ));

  final TokenReader _tokenReader;
  final void Function()? onUnauthorized;
  final Dio _dio;

  /// Used only for pre-signed download URLs returned by GitHub (no auth header,
  /// because the blob storage rejects duplicate authentication).
  final Dio _external;

  // ---------------------------------------------------------------- core

  Future<Response<dynamic>> _send(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    ResponseType responseType = ResponseType.json,
    bool followRedirects = true,
  }) async {
    final token = _tokenReader();
    if (token == null || token.isEmpty) {
      throw const AppFailure(FailureKind.unauthorized);
    }
    final Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: responseType,
          followRedirects: followRedirects,
          validateStatus: (_) => true,
          contentType: data == null ? null : Headers.jsonContentType,
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': AppConfig.githubApiVersion,
            'User-Agent': AppConfig.userAgent,
            'Authorization': 'Bearer $token',
          },
        ),
      );
    } on DioException catch (e) {
      throw networkFailure(e);
    }
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return res;
    if (!followRedirects && status >= 300 && status < 400) return res;
    throw failureFrom(res);
  }

  static AppFailure networkFailure(DioException e) {
    final isTimeout = e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout;
    return AppFailure(
      isTimeout ? FailureKind.timeout : FailureKind.network,
      detail: SecretRedactor.redact(e.message ?? e.type.name),
    );
  }

  /// Converts an HTTP error response to a typed failure. Visible for tests.
  AppFailure failureFrom(Response<dynamic> res) {
    final status = res.statusCode ?? 0;
    final message = SecretRedactor.redact(_messageOf(res.data));
    final remaining = res.headers.value('x-ratelimit-remaining');
    final resetRaw = res.headers.value('x-ratelimit-reset');
    final retryRaw = res.headers.value('retry-after');
    final resetAt = resetRaw == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((int.tryParse(resetRaw) ?? 0) * 1000);
    final retryAfter = retryRaw == null ? null : Duration(seconds: int.tryParse(retryRaw) ?? 60);

    switch (status) {
      case 401:
        onUnauthorized?.call();
        return AppFailure(FailureKind.unauthorized, detail: message);
      case 403:
      case 429:
        final limited = status == 429 ||
            remaining == '0' ||
            retryRaw != null ||
            message.toLowerCase().contains('rate limit');
        if (limited) {
          return AppFailure(FailureKind.rateLimited,
              detail: message, resetAt: resetAt, retryAfter: retryAfter);
        }
        return AppFailure(FailureKind.forbidden, detail: message);
      case 404:
        return AppFailure(FailureKind.notFound, detail: message);
      case 409:
        return AppFailure(FailureKind.conflict, detail: message);
      case 422:
        return AppFailure(FailureKind.validation, detail: message);
      default:
        if (status >= 500) return AppFailure(FailureKind.server, detail: message);
        return AppFailure(FailureKind.unknown, detail: message);
    }
  }

  static String _messageOf(Object? data) {
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (data is String && data.isNotEmpty) {
      return data.length > 200 ? data.substring(0, 200) : data;
    }
    return '';
  }

  static Map<String, dynamic> _map(Object? v) => asJsonMap(v);
  static List<dynamic> _list(Object? v) => v is List ? v : const [];

  static String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  static String _workflowId(String workflowPath) => workflowPath.split('/').last;

  // ---------------------------------------------------------------- account

  Future<({GitHubUser user, List<String> scopes})> currentUser() async {
    final res = await _send('GET', '/user');
    final scopes = (res.headers.value('x-oauth-scopes') ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return (user: GitHubUser.fromJson(_map(res.data)), scopes: scopes);
  }

  // ---------------------------------------------------------------- repos

  /// Lists repositories the user can access (owner, collaborator, org member).
  Future<List<RepoSummary>> listRepositories({int maxPages = 10}) async {
    final out = <RepoSummary>[];
    for (var page = 1; page <= maxPages; page++) {
      final res = await _send('GET', '/user/repos', query: {
        'affiliation': 'owner,collaborator,organization_member',
        'sort': 'updated',
        'per_page': 100,
        'page': page,
      });
      final items = _list(res.data);
      out.addAll(items.map((e) => RepoSummary.fromJson(_map(e))));
      if (items.length < 100) break;
    }
    return out;
  }

  Future<RepoSummary> createRepository({
    required String name,
    required bool isPrivate,
    String? description,
  }) async {
    final res = await _send('POST', '/user/repos', data: {
      'name': name,
      'private': isPrivate,
      'description': description ?? '',
      'auto_init': true,
    });
    return RepoSummary.fromJson(_map(res.data));
  }

  /// Returns true/false when readable, null when the token cannot read it.
  Future<bool?> actionsEnabled(String owner, String repo) async {
    try {
      final res = await _send('GET', '/repos/$owner/$repo/actions/permissions');
      return _map(res.data)['enabled'] as bool?;
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.forbidden || e.kind == FailureKind.notFound) return null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------- contents

  Future<RepoFile?> getFile(String owner, String repo, String path, {String? ref}) async {
    try {
      final res = await _send(
        'GET',
        '/repos/$owner/$repo/contents/${_encodePath(path)}',
        query: ref == null ? null : {'ref': ref},
      );
      final map = _map(res.data);
      final encoded = (map['content'] as String? ?? '').replaceAll('\n', '');
      final content = encoded.isEmpty ? '' : utf8.decode(base64.decode(encoded));
      return RepoFile(
        path: map['path'] as String? ?? path,
        sha: map['sha'] as String? ?? '',
        content: content,
        htmlUrl: map['html_url'] as String?,
      );
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.notFound) return null;
      rethrow;
    }
  }

  Future<void> putFile({
    required String owner,
    required String repo,
    required String path,
    required String content,
    required String message,
    required String branch,
    String? sha,
  }) async {
    await _send('PUT', '/repos/$owner/$repo/contents/${_encodePath(path)}', data: {
      'message': message,
      'content': base64.encode(utf8.encode(content)),
      'branch': branch,
      if (sha != null) 'sha': sha,
    });
  }

  // ---------------------------------------------------------------- secrets

  /// Checks that a secret exists (metadata only, the value is never readable).
  /// Returns null if the token lacks permission to read secret metadata.
  Future<bool?> secretExists(String owner, String repo, String name) async {
    try {
      await _send('GET', '/repos/$owner/$repo/actions/secrets/$name');
      return true;
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.notFound) return false;
      if (e.kind == FailureKind.forbidden) return null;
      rethrow;
    }
  }

  /// Repo Actions public key used to encrypt secrets (libsodium sealed box).
  Future<({String keyId, String key})> actionsPublicKey(String owner, String repo) async {
    final res = await _send('GET', '/repos/$owner/$repo/actions/secrets/public-key');
    final data = res.data;
    if (data is! Map || data['key_id'] == null || data['key'] == null) {
      throw const AppFailure(FailureKind.server);
    }
    return (keyId: data['key_id'].toString(), key: data['key'].toString());
  }

  /// Creates or updates an Actions secret. [encryptedValue] must already be
  /// sealed with the repo public key; the plaintext never leaves the device.
  Future<void> putActionsSecret(
    String owner,
    String repo,
    String name, {
    required String encryptedValue,
    required String keyId,
  }) async {
    await _send(
      'PUT',
      '/repos/$owner/$repo/actions/secrets/$name',
      data: {'encrypted_value': encryptedValue, 'key_id': keyId},
    );
  }

  // ---------------------------------------------------------------- workflows

  Future<void> dispatchWorkflow({
    required String owner,
    required String repo,
    required String workflowPath,
    required String ref,
    required Map<String, Object> inputs,
  }) async {
    await _send(
      'POST',
      '/repos/$owner/$repo/actions/workflows/${Uri.encodeComponent(_workflowId(workflowPath))}/dispatches',
      data: {'ref': ref, 'inputs': inputs},
    );
  }

  Future<List<WorkflowRun>> listRuns({
    required String owner,
    required String repo,
    String? workflowPath,
    String? event,
    int perPage = 30,
    int page = 1,
  }) async {
    final base = workflowPath == null
        ? '/repos/$owner/$repo/actions/runs'
        : '/repos/$owner/$repo/actions/workflows/${Uri.encodeComponent(_workflowId(workflowPath))}/runs';
    final res = await _send('GET', base, query: {
      'per_page': perPage,
      'page': page,
      if (event != null) 'event': event,
    });
    return _list(_map(res.data)['workflow_runs'])
        .map((e) => WorkflowRun.fromJson(_map(e)))
        .toList();
  }

  Future<WorkflowRun> getRun(String owner, String repo, int runId) async {
    final res = await _send('GET', '/repos/$owner/$repo/actions/runs/$runId');
    return WorkflowRun.fromJson(_map(res.data));
  }

  Future<void> cancelRun(String owner, String repo, int runId) async {
    await _send('POST', '/repos/$owner/$repo/actions/runs/$runId/cancel');
  }

  Future<List<WorkflowJob>> listJobs(String owner, String repo, int runId) async {
    final res = await _send('GET', '/repos/$owner/$repo/actions/runs/$runId/jobs',
        query: {'per_page': 100});
    return _list(_map(res.data)['jobs']).map((e) => WorkflowJob.fromJson(_map(e))).toList();
  }

  /// Downloads the plain-text log of a job. GitHub answers with a redirect to a
  /// pre-signed URL; we follow it manually without the Authorization header.
  /// Returns an empty string when logs are not available yet.
  Future<String> jobLogs(String owner, String repo, int jobId) async {
    final res = await _send(
      'GET',
      '/repos/$owner/$repo/actions/jobs/$jobId/logs',
      followRedirects: false,
      responseType: ResponseType.plain,
    );
    if (res.statusCode == 200) return (res.data ?? '').toString();
    final location = res.headers.value('location');
    if (location == null) return '';
    try {
      final body = await _external.get<String>(
        location,
        options: Options(responseType: ResponseType.plain),
      );
      return body.data ?? '';
    } on DioException catch (e) {
      throw networkFailure(e);
    }
  }

  // ---------------------------------------------------------------- artifacts

  Future<List<ArtifactInfo>> listArtifacts(String owner, String repo, int runId) async {
    final res = await _send('GET', '/repos/$owner/$repo/actions/runs/$runId/artifacts',
        query: {'per_page': 100});
    return _list(_map(res.data)['artifacts'])
        .map((e) => ArtifactInfo.fromJson(_map(e)))
        .toList();
  }

  Future<void> downloadArtifact({
    required String owner,
    required String repo,
    required int artifactId,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    final res = await _send(
      'GET',
      '/repos/$owner/$repo/actions/artifacts/$artifactId/zip',
      followRedirects: false,
      responseType: ResponseType.plain,
    );
    final location = res.headers.value('location');
    if (location == null) {
      throw const AppFailure(FailureKind.unknown, detail: 'missing download location');
    }
    try {
      await _external.download(
        location,
        savePath,
        onReceiveProgress: onProgress,
        deleteOnError: true,
      );
    } on DioException catch (e) {
      throw networkFailure(e);
    }
  }
}
