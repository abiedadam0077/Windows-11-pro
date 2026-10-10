import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/api.dart';
import 'package:pinenacl/x25519.dart' show SealedBox;
import 'package:winpilot/core/config/app_config.dart';
import 'package:winpilot/core/errors/app_failure.dart';
import 'package:winpilot/data/services/github_api.dart';
import 'package:winpilot/data/services/github_secrets.dart';

// Test-only key pair. It protects nothing; it only lets the test open what the app uploads.
final _sk = base64Decode('AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=');
final _pk = base64Decode('B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw=');

// Produced by libsodium (PyNaCl SealedBox) for the value below. Independent of Dart code.
const _libsodiumCiphertext =
    '1+2xuHNER3Oh4FEnab+XNPOkGyWEem4tg7hBMQiQLH0W/96VYEy/OBuatUkHYpb/vaRvn1GA19gyky7nj314JZJkKVV7bZIwrIFcqNA=';
const _libsodiumPlain = 'winpilot test value é ملم';

class _Fake implements HttpClientAdapter {
  _Fake(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) => handler(o);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, String body) =>
    ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

void main() {
  group('Secret names (unit)', () {
    test('the three names are exactly the ones the workflow reads', () {
      expect(AppConfig.backupPasswordSecret, 'BACKUP_PASSWORD');
      expect(AppConfig.accessPasswordSecret, 'ACCESS_PASSWORD');
      expect(AppConfig.tailscaleAuthKeySecret, 'TS_AUTHKEY');
    });
  });

  group('Sealing is compatible with GitHub (libsodium crypto_box_seal)', () {
    test('a value sealed by libsodium opens with the repo private key in Dart', () {
      final opened = SealedBox(PrivateKey(Uint8List.fromList(_sk)))
          .decrypt(base64Decode(_libsodiumCiphertext));
      expect(utf8.decode(opened), _libsodiumPlain);
    });
  });

  group('Secret write flow through the GitHub API (unit, fake HTTP)', () {
    test('uploads the value encrypted with the repo key and confirms it exists', () async {
      Map<String, dynamic>? uploaded;
      var secretPresent = false;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
        ..httpClientAdapter = _Fake((o) async {
          final p = o.uri.path;
          if (o.method == 'GET' && p.endsWith('/actions/secrets/public-key')) {
            return _json(200, jsonEncode({'key_id': 'kid-123', 'key': base64Encode(_pk)}));
          }
          if (o.method == 'PUT' && p == '/repos/o/r/actions/secrets/ACCESS_PASSWORD') {
            uploaded = Map<String, dynamic>.from(o.data as Map);
            secretPresent = true;
            return _json(201, '');
          }
          if (o.method == 'GET' && p == '/repos/o/r/actions/secrets/ACCESS_PASSWORD') {
            return secretPresent ? _json(200, '{"name":"ACCESS_PASSWORD"}') : _json(404, '{"message":"Not Found"}');
          }
          return _json(500, '{"message":"unexpected ${o.method} $p"}');
        });
      final api = GitHubApi(tokenReader: () => 'test-token', dio: dio, externalDio: Dio());
      final ok = await GitHubSecretsWriter(api).write(
        owner: 'o',
        repo: 'r',
        name: 'ACCESS_PASSWORD',
        value: 'Win-Pass_42!xyz',
      );

      expect(ok, isTrue, reason: 'GitHub must report the secret present afterwards');
      expect(uploaded!['key_id'], 'kid-123', reason: 'the upload must reference the key it was sealed with');
      final cipher = base64Decode(uploaded!['encrypted_value'] as String);
      expect(utf8.decode(SealedBox(PrivateKey(Uint8List.fromList(_sk))).decrypt(cipher)), 'Win-Pass_42!xyz');
      expect(uploaded!.toString(), isNot(contains('Win-Pass_42!xyz')), reason: 'plaintext must never be sent');
    });

    test('reports failure when GitHub does not show the secret afterwards', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
        ..httpClientAdapter = _Fake((o) async {
          if (o.method == 'GET' && o.uri.path.endsWith('/public-key')) {
            return _json(200, jsonEncode({'key_id': 'k', 'key': base64Encode(_pk)}));
          }
          if (o.method == 'PUT') return _json(201, '');
          return _json(404, '{"message":"Not Found"}');
        });
      final api = GitHubApi(tokenReader: () => 'test-token', dio: dio, externalDio: Dio());
      expect(
        await GitHubSecretsWriter(api).write(owner: 'o', repo: 'r', name: 'TS_AUTHKEY', value: 'tskey-x'),
        isFalse,
      );
    });

    test('a broken public key response is a server failure, not a silent success', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.github.com'))
        ..httpClientAdapter = _Fake((o) async => _json(200, '{"unexpected":true}'));
      final api = GitHubApi(tokenReader: () => 'test-token', dio: dio, externalDio: Dio());
      await expectLater(
        GitHubSecretsWriter(api).write(owner: 'o', repo: 'r', name: 'BACKUP_PASSWORD', value: 'x' * 20),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
