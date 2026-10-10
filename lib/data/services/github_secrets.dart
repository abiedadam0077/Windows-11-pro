import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/api.dart';

import '../../core/errors/app_failure.dart';
import 'github_api.dart';

/// Writes Actions secrets through the GitHub REST API.
///
/// GitHub requires each value to be sealed with the repository's public key
/// (libsodium `crypto_box_seal`) before upload. Plaintext is only held in
/// memory for the duration of the call and is never logged or persisted.
class GitHubSecretsWriter {
  GitHubSecretsWriter(this._api);

  final GitHubApi _api;

  /// Encrypts [plainText] for GitHub with [publicKeyB64] (base64, 32 bytes).
  static String sealForGitHub(String plainText, String publicKeyB64) {
    final keyBytes = base64Decode(publicKeyB64);
    if (keyBytes.length != 32) {
      throw const AppFailure(FailureKind.server);
    }
    final box = SealedBox(PublicKey(Uint8List.fromList(keyBytes)));
    final cipher = box.encrypt(Uint8List.fromList(utf8.encode(plainText)));
    return base64Encode(cipher);
  }

  /// Writes [name] and then confirms the secret exists. Returns true only if
  /// GitHub reports the secret present afterwards.
  Future<bool> write({
    required String owner,
    required String repo,
    required String name,
    required String value,
  }) async {
    final key = await _api.actionsPublicKey(owner, repo);
    final sealed = sealForGitHub(value, key.key);
    await _api.putActionsSecret(
      owner,
      repo,
      name,
      encryptedValue: sealed,
      keyId: key.keyId,
    );
    return (await _api.secretExists(owner, repo, name)) == true;
  }
}
