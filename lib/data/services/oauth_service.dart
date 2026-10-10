import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';

/// One login attempt: PKCE verifier/challenge plus anti-CSRF state.
/// The client secret is intentionally absent (public native client + PKCE).
class OAuthAttempt {
  OAuthAttempt._(this.verifier, this.state);

  final String verifier;
  final String state;

  String get challenge =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  factory OAuthAttempt.create({Random? random}) {
    final rnd = random ?? Random.secure();
    return OAuthAttempt._(_randomUrlSafe(rnd, 64), _randomUrlSafe(rnd, 32));
  }

  Uri authorizeUri(String clientId) => Uri.https('github.com', '/login/oauth/authorize', {
        'client_id': clientId,
        'redirect_uri': AppConfig.oauthRedirectUri,
        'scope': AppConfig.oauthScopes,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'allow_signup': 'true',
      });

  static const _unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static String _randomUrlSafe(Random rnd, int length) =>
      List.generate(length, (_) => _unreserved[rnd.nextInt(_unreserved.length)]).join();
}

class OAuthService {
  OAuthService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;

  /// Exchanges the authorization code for an access token using PKCE.
  Future<String> exchangeCode({
    required String clientId,
    required String code,
    required String verifier,
  }) async {
    final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        '${AppConfig.githubWebBase}/login/oauth/access_token',
        data: {
          'client_id': clientId,
          'code': code,
          'code_verifier': verifier,
          'redirect_uri': AppConfig.oauthRedirectUri,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Accept': 'application/json', 'User-Agent': AppConfig.userAgent},
          validateStatus: (_) => true,
        ),
      );
    } on DioException {
      throw const AppFailure(FailureKind.network);
    }
    final raw = res.data;
    final Map<String, dynamic> body = raw is Map
        ? Map<String, dynamic>.from(raw)
        : raw is String
            ? Uri.splitQueryString(raw)
            : <String, dynamic>{};
    final token = body['access_token'];
    if (token is String && token.isNotEmpty) return token;
    final description = body['error_description']?.toString();
    throw AppFailure(
      FailureKind.unauthorized,
      detail: description ?? body['error']?.toString() ?? 'token_exchange_failed',
    );
  }
}
