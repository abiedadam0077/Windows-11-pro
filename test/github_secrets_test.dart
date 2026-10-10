import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/api.dart';
import 'package:pinenacl/x25519.dart' show SealedBox;
import 'package:winpilot/core/utils/validators.dart';
import 'package:winpilot/data/services/github_secrets.dart';

void main() {
  group('GitHub Actions secret sealing (unit)', () {
    test('sealed box output is plaintext + 48 bytes (ephemeral key + MAC)', () {
      final priv = PrivateKey.generate();
      final pubB64 = base64Encode(priv.publicKey.asTypedList);
      const plain = 'Example-Passw0rd!';
      final sealed = base64Decode(GitHubSecretsWriter.sealForGitHub(plain, pubB64));
      expect(sealed.length, utf8.encode(plain).length + 48);
    });

    test('round-trips: the repo private key can open the sealed value', () {
      final priv = PrivateKey.generate();
      final pubB64 = base64Encode(priv.publicKey.asTypedList);
      const plain = 'Win-User-Pass_42!xyz';
      final sealed = GitHubSecretsWriter.sealForGitHub(plain, pubB64);
      final opened = SealedBox(priv).decrypt(base64Decode(sealed));
      expect(utf8.decode(opened), plain);
    });

    test('rejects a public key that is not 32 bytes', () {
      final bad = base64Encode(Uint8List(16));
      expect(() => GitHubSecretsWriter.sealForGitHub('x', bad), throwsA(anything));
    });

    test('two seals of the same value differ (sealed box uses ephemeral keys)', () {
      final priv = PrivateKey.generate();
      final pubB64 = base64Encode(priv.publicKey.asTypedList);
      final a = GitHubSecretsWriter.sealForGitHub('same', pubB64);
      final b = GitHubSecretsWriter.sealForGitHub('same', pubB64);
      expect(a == b, isFalse);
    });
  });

  group('Password policy used by the secrets screen (unit)', () {
    test('generated password satisfies every rule', () {
      for (var i = 0; i < 20; i++) {
        final pw = PasswordPolicy.generate(length: 24);
        expect(PasswordPolicy.violations(pw), isEmpty);
        expect(pw.length, 24);
      }
    });

    test('reports short passwords and passwords containing the username', () {
      expect(PasswordPolicy.violations('Ab1!'), contains('pw_rule_length'));
      expect(
        PasswordPolicy.violations('Winuser-Abc123!xy', username: 'winuser'),
        contains('pw_rule_username'),
      );
    });
  });
}
