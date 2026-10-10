import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the GitHub OAuth access token in the Android Keystore-backed store.
class AccessTokenStore {
  AccessTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'github_access_token_v1';

  Future<String?> read() => _storage.read(key: _tokenKey);

  Future<void> write(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clear() => _storage.delete(key: _tokenKey);
}

/// In-memory holder read by the API client. The token is never logged.
class AccessTokenHolder {
  String? token;
}
