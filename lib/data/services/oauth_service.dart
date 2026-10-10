import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';

/// GitHub OAuth **Device Flow** (RFC 8628).
///
/// Why device flow: the OAuth *web* flow requires a `client_secret` when
/// exchanging the code, and a secret cannot be shipped inside an APK. The
/// device flow needs only the public Client ID, so no secret is ever stored
/// or sent by WinPilot. The user approves the request on github.com in the
/// browser; WinPilot never sees a GitHub password.
///
/// Prerequisite (documented in the app): the OAuth App must have
/// "Enable Device Flow" turned on in its GitHub settings.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration expiresIn;
  final Duration interval;
}

/// Result of one poll of the token endpoint.
sealed class DevicePollOutcome {
  const DevicePollOutcome();
}

class DevicePollPending extends DevicePollOutcome {
  const DevicePollPending({this.slowDown = false});

  /// True when GitHub asked us to increase the interval by 5 seconds.
  final bool slowDown;
}

class DevicePollToken extends DevicePollOutcome {
  const DevicePollToken(this.accessToken, this.scope);

  final String accessToken;
  final String scope;
}

class DevicePollFailed extends DevicePollOutcome {
  const DevicePollFailed(this.failure);

  final AppFailure failure;
}

/// Pure interpretation of GitHub's device-flow JSON responses. No I/O: this
/// is what the unit tests exercise.
abstract final class DeviceFlowParser {
  static const _grant = 'urn:ietf:params:oauth:grant-type:device_code';

  static String get grantType => _grant;

  /// Parses the body of `POST /login/device/code`.
  static DeviceCode parseDeviceCode(Map<String, dynamic> body) {
    final error = body['error']?.toString();
    if (error != null) throw _failureForError(error, body['error_description']?.toString());
    final device = body['device_code'];
    final user = body['user_code'];
    final uri = body['verification_uri'];
    if (device is! String || device.isEmpty || user is! String || user.isEmpty) {
      throw const AppFailure(FailureKind.server, detail: 'malformed device code response');
    }
    final expires = _asInt(body['expires_in']) ?? 900;
    final interval = _asInt(body['interval']) ?? 5;
    return DeviceCode(
      deviceCode: device,
      userCode: user,
      verificationUri: uri is String && uri.isNotEmpty ? uri : 'https://github.com/login/device',
      expiresIn: Duration(seconds: expires),
      interval: Duration(seconds: interval),
    );
  }

  /// Interprets one response of `POST /login/oauth/access_token` during polling.
  static DevicePollOutcome interpretTokenBody(Map<String, dynamic> body) {
    final token = body['access_token'];
    if (token is String && token.isNotEmpty) {
      return DevicePollToken(token, body['scope']?.toString() ?? '');
    }
    final error = body['error']?.toString();
    switch (error) {
      case 'authorization_pending':
        return const DevicePollPending();
      case 'slow_down':
        return const DevicePollPending(slowDown: true);
      case null:
        return const DevicePollFailed(
          AppFailure(FailureKind.unknown, detail: 'token response had no access_token'),
        );
      default:
        return DevicePollFailed(_failureForError(error, body['error_description']?.toString()));
    }
  }

  /// Maps GitHub OAuth error codes to user-safe failures.
  static AppFailure _failureForError(String error, String? description) => switch (error) {
        'access_denied' => const AppFailure(FailureKind.cancelled),
        'expired_token' => const AppFailure(FailureKind.timeout, detail: 'code expired'),
        'device_flow_disabled' => const AppFailure(FailureKind.notConfigured,
            detail: 'device flow disabled for this OAuth App'),
        'incorrect_client_credentials' ||
        'unauthorized_client' =>
          const AppFailure(FailureKind.notConfigured, detail: 'client id rejected'),
        'incorrect_device_code' => const AppFailure(FailureKind.unauthorized, detail: 'bad device code'),
        'unsupported_grant_type' => const AppFailure(FailureKind.server, detail: 'grant unsupported'),
        _ => AppFailure(FailureKind.unauthorized, detail: description ?? error),
      };

  static int? _asInt(Object? v) => v is int ? v : (v is String ? int.tryParse(v) : null);
}

class OAuthService {
  OAuthService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;

  static const _scope = AppConfig.oauthScopes;

  /// Step 1: asks GitHub for a device code and a user code to show the user.
  Future<DeviceCode> requestDeviceCode(String clientId) async {
    final body = await _post('${AppConfig.githubWebBase}/login/device/code', {
      'client_id': clientId,
      'scope': _scope,
    });
    return DeviceFlowParser.parseDeviceCode(body);
  }

  /// Step 2: polls until the user approves, denies, the code expires, or
  /// [isCancelled] returns true. Honours GitHub's interval and `slow_down`.
  Future<String> pollForToken({
    required String clientId,
    required DeviceCode code,
    required bool Function() isCancelled,
    Future<void> Function(Duration)? wait,
  }) async {
    final sleep = wait ?? Future<void>.delayed;
    var interval = code.interval;
    final deadline = DateTime.now().add(code.expiresIn);
    while (true) {
      if (isCancelled()) throw const AppFailure(FailureKind.cancelled);
      if (DateTime.now().isAfter(deadline)) throw const AppFailure(FailureKind.timeout);
      await sleep(interval);
      if (isCancelled()) throw const AppFailure(FailureKind.cancelled);
      final body = await _post('${AppConfig.githubWebBase}/login/oauth/access_token', {
        'client_id': clientId,
        'device_code': code.deviceCode,
        'grant_type': DeviceFlowParser.grantType,
      });
      final outcome = DeviceFlowParser.interpretTokenBody(body);
      switch (outcome) {
        case DevicePollToken(:final accessToken):
          return accessToken;
        case DevicePollPending(:final slowDown):
          if (slowDown) interval += const Duration(seconds: 5);
        case DevicePollFailed(:final failure):
          throw failure;
      }
    }
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, String> form) async {
    final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        url,
        data: form,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Accept': 'application/json', 'User-Agent': AppConfig.userAgent},
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const AppFailure(FailureKind.timeout);
      }
      throw const AppFailure(FailureKind.network);
    }
    final raw = res.data;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) return Uri.splitQueryString(raw);
    throw AppFailure(FailureKind.server, detail: 'HTTP ${res.statusCode}');
  }
}
