import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/errors/app_failure.dart';
import 'package:winpilot/data/services/oauth_service.dart';

/// Answers each POST with the next scripted JSON body, without touching the network.
class _ScriptedAdapter extends Interceptor {
  _ScriptedAdapter(this.bodies);

  final List<Map<String, dynamic>> bodies;
  final List<Map<String, dynamic>> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(Map<String, dynamic>.from(options.data as Map));
    final body = bodies.removeAt(0);
    handler.resolve(Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: body,
    ));
  }
}

Dio _dioWith(_ScriptedAdapter adapter) {
  final dio = Dio();
  dio.interceptors.add(adapter);
  return dio;
}

void main() {
  group('device code response', () {
    test('parses the documented fields', () {
      final code = DeviceFlowParser.parseDeviceCode({
        'device_code': '3584d83530557fdd1f46af8289938c8ef79f9dc5',
        'user_code': 'WDJB-MJHT',
        'verification_uri': 'https://github.com/login/device',
        'expires_in': 900,
        'interval': 5,
      });
      expect(code.userCode, 'WDJB-MJHT');
      expect(code.expiresIn, const Duration(seconds: 900));
      expect(code.interval, const Duration(seconds: 5));
    });

    test('maps device_flow_disabled to a configuration failure', () {
      expect(
        () => DeviceFlowParser.parseDeviceCode({'error': 'device_flow_disabled'}),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.notConfigured)),
      );
    });

    test('rejects a malformed body', () {
      expect(
        () => DeviceFlowParser.parseDeviceCode({'user_code': 'X'}),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.server)),
      );
    });
  });

  group('token poll interpretation', () {
    test('access_token is success', () {
      final r = DeviceFlowParser.interpretTokenBody({
        'access_token': 'gho_example',
        'token_type': 'bearer',
        'scope': 'repo,workflow',
      });
      expect(r, isA<DevicePollToken>());
      expect((r as DevicePollToken).accessToken, 'gho_example');
    });

    test('authorization_pending keeps polling', () {
      final r = DeviceFlowParser.interpretTokenBody({'error': 'authorization_pending'});
      expect(r, isA<DevicePollPending>());
      expect((r as DevicePollPending).slowDown, isFalse);
    });

    test('slow_down asks for a longer interval', () {
      final r = DeviceFlowParser.interpretTokenBody({'error': 'slow_down'});
      expect((r as DevicePollPending).slowDown, isTrue);
    });

    test('terminal errors map to user-safe failures', () {
      FailureKind kindOf(String error) {
        final r = DeviceFlowParser.interpretTokenBody({'error': error});
        return (r as DevicePollFailed).failure.kind;
      }

      expect(kindOf('access_denied'), FailureKind.cancelled);
      expect(kindOf('expired_token'), FailureKind.timeout);
      expect(kindOf('incorrect_device_code'), FailureKind.unauthorized);
      expect(kindOf('incorrect_client_credentials'), FailureKind.notConfigured);
      expect(kindOf('device_flow_disabled'), FailureKind.notConfigured);
    });
  });

  group('pollForToken', () {
    DeviceCode code() => const DeviceCode(
          deviceCode: 'dc',
          userCode: 'ABCD-1234',
          verificationUri: 'https://github.com/login/device',
          expiresIn: Duration(minutes: 15),
          interval: Duration(seconds: 5),
        );

    test('waits through pending and slow_down, then returns the token', () async {
      final adapter = _ScriptedAdapter([
        {'error': 'authorization_pending'},
        {'error': 'slow_down'},
        {'access_token': 'tok', 'scope': 'repo'},
      ]);
      final waits = <Duration>[];
      final token = await OAuthService(dio: _dioWith(adapter)).pollForToken(
        clientId: 'Ov23liabcdefghijklmn',
        code: code(),
        isCancelled: () => false,
        wait: (d) async => waits.add(d),
      );
      expect(token, 'tok');
      // First wait uses the given interval, then it grows by 5s after slow_down.
      expect(waits, [
        const Duration(seconds: 5),
        const Duration(seconds: 5),
        const Duration(seconds: 10),
      ]);
    });

    test('sends no client_secret and uses the device grant type', () async {
      final adapter = _ScriptedAdapter([
        {'access_token': 'tok'},
      ]);
      await OAuthService(dio: _dioWith(adapter)).pollForToken(
        clientId: 'Ov23liabcdefghijklmn',
        code: code(),
        isCancelled: () => false,
        wait: (_) async {},
      );
      final sent = adapter.requests.single;
      expect(sent.containsKey('client_secret'), isFalse);
      expect(sent.containsKey('code_verifier'), isFalse);
      expect(sent['grant_type'], 'urn:ietf:params:oauth:grant-type:device_code');
      expect(sent['device_code'], 'dc');
    });

    test('stops when the user cancels, without calling GitHub again', () async {
      final adapter = _ScriptedAdapter([]);
      var cancelled = false;
      await expectLater(
        OAuthService(dio: _dioWith(adapter)).pollForToken(
          clientId: 'Ov23liabcdefghijklmn',
          code: code(),
          isCancelled: () => cancelled,
          wait: (_) async => cancelled = true,
        ),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled)),
      );
      expect(adapter.requests, isEmpty);
    });

    test('access_denied surfaces as cancelled', () async {
      final adapter = _ScriptedAdapter([
        {'error': 'access_denied'},
      ]);
      await expectLater(
        OAuthService(dio: _dioWith(adapter)).pollForToken(
          clientId: 'Ov23liabcdefghijklmn',
          code: code(),
          isCancelled: () => false,
          wait: (_) async {},
        ),
        throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled)),
      );
    });
  });
}
