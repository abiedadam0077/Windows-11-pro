import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/utils/app_version.dart';
import 'package:winpilot/core/utils/validators.dart';
import 'package:winpilot/data/services/update_service.dart';
import 'package:winpilot/core/errors/app_failure.dart';

void main() {
  group('GitHub OAuth Client ID validation', () {
    test('accepts OAuth App client IDs', () {
      expect(Validators.isValidClientId('Ov23liAbCdEfGhIjKlMn'), isTrue);
      expect(Validators.isValidClientId('  Ov23liAbCdEfGhIjKlMn  '), isTrue);
      expect(Validators.isValidClientId('0123456789abcdef0123'), isTrue);
    });

    test('rejects empty and malformed values', () {
      expect(Validators.isValidClientId(''), isFalse);
      expect(Validators.isValidClientId('hello world'), isFalse);
      expect(Validators.isValidClientId('Ov23'), isFalse);
    });

    test('rejects a value shaped like a client secret', () {
      const secret = '0123456789abcdef0123456789abcdef01234567';
      expect(Validators.isLikelyClientSecret(secret), isTrue);
      expect(Validators.isValidClientId(secret), isFalse);
    });
  });

  group('version comparison', () {
    test('parses x.y.z with optional v prefix', () {
      expect(AppVersion.tryParse('1.1.0'), const AppVersion(1, 1, 0));
      expect(AppVersion.tryParse('v2.0'), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse('nope'), isNull);
      expect(AppVersion.tryParse('1.0.0-beta'), isNull);
    });

    test('orders versions numerically, not as strings', () {
      expect(AppVersion.tryParse('1.10.0')! > AppVersion.tryParse('1.9.9')!, isTrue);
      expect(AppVersion.tryParse('1.1.0')! > AppVersion.tryParse('1.1.0')!, isFalse);
      expect(AppVersion.tryParse('1.0.1')! > AppVersion.tryParse('1.1.0')!, isFalse);
    });
  });

  group('update manifest', () {
    final sha = 'a' * 64;
    Map<String, dynamic> good() => {
          'version': '1.1.0',
          'versionCode': 42,
          'sha256': sha,
        };

    test('parses a valid manifest', () {
      final info = UpdateService.parseManifest(good(),
          apkUrl: 'https://github.com/x/y/releases/download/t/WinPilot-release.apk',
          releaseUrl: 'https://github.com/x/y/releases/tag/t');
      expect(info.versionCode, 42);
      expect(info.sha256, sha);
    });

    test('rejects a missing or malformed checksum', () {
      final bad = good()..['sha256'] = 'xyz';
      expect(
        () => UpdateService.parseManifest(bad, apkUrl: 'https://a', releaseUrl: ''),
        throwsA(isA<AppFailure>()),
      );
    });

    test('rejects a non-HTTPS download URL', () {
      expect(
        () => UpdateService.parseManifest(good(), apkUrl: 'http://insecure', releaseUrl: ''),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
