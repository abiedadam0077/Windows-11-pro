import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_failure.dart';
import '../models/github_models.dart';
import '../data/services/oauth_service.dart';
import 'providers.dart';
import 'session_state.dart';
import 'settings_state.dart';

enum AuthStatus { unknown, signedOut, signingIn, signedIn, expired, failed }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.scopes = const [],
    this.failure,
    this.offline = false,
    this.deviceCode,
  });

  final AuthStatus status;
  final GitHubUser? user;
  final List<String> scopes;
  final AppFailure? failure;

  /// True when the profile could not be refreshed due to connectivity.
  final bool offline;

  /// Device-flow code shown to the user while [AuthStatus.signingIn].
  final DeviceCode? deviceCode;

  bool get isSignedIn => status == AuthStatus.signedIn || status == AuthStatus.expired;

  /// Classic OAuth scopes: `workflow` is needed to write workflow files.
  bool get canWriteWorkflows => scopes.contains('workflow');

  bool get hasRepoScope => scopes.contains('repo');
}

class AuthController extends Notifier<AuthState> {
  /// Incremented by every sign-in attempt and by cancellation. A polling loop
  /// whose id no longer matches is stale and must not touch the state.
  int _attemptSeq = 0;

  @override
  AuthState build() => const AuthState();

  /// Restores a previous session from secure storage without blocking the UI
  /// for longer than the network request allows.
  Future<void> restore() async {
    final token = await ref.read(accessTokenStoreProvider).read();
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }
    ref.read(tokenHolderProvider).token = token;
    state = AuthState(status: AuthStatus.signedIn, user: _cachedUser());
    await refreshProfile();
  }

  Future<void> refreshProfile() async {
    try {
      final result = await ref.read(githubApiProvider).currentUser();
      _cacheUser(result.user);
      state = AuthState(
        status: AuthStatus.signedIn,
        user: result.user,
        scopes: result.scopes,
      );
    } on AppFailure catch (e) {
      switch (e.kind) {
        case FailureKind.unauthorized:
          await _expire();
          break;
        case FailureKind.network:
        case FailureKind.timeout:
          state = AuthState(
            status: state.status == AuthStatus.unknown ? AuthStatus.signedIn : state.status,
            user: state.user,
            scopes: state.scopes,
            offline: true,
          );
          break;
        default:
          state = AuthState(
            status: AuthStatus.signedIn,
            user: state.user,
            scopes: state.scopes,
            failure: e,
          );
          break;
      }
    }
  }

  /// GitHub Device Flow. The user opens github.com/login/device and enters
  /// [AuthState.deviceCode.userCode]; WinPilot polls until approval, denial,
  /// expiry, or cancellation. No client secret and no password is involved.
  Future<void> signIn() async {
    final clientId = ref.read(settingsProvider).effectiveClientId;
    if (clientId.isEmpty) {
      state = const AuthState(
        status: AuthStatus.failed,
        failure: AppFailure(FailureKind.notConfigured),
      );
      return;
    }
    final attempt = ++_attemptSeq;
    bool isCurrent() => attempt == _attemptSeq;
    final oauth = ref.read(oauthServiceProvider);
    state = const AuthState(status: AuthStatus.signingIn);
    try {
      final code = await oauth.requestDeviceCode(clientId);
      if (!isCurrent()) return;
      state = AuthState(status: AuthStatus.signingIn, deviceCode: code);
      final token = await oauth.pollForToken(
        clientId: clientId,
        code: code,
        isCancelled: () => !isCurrent(),
      );
      if (!isCurrent()) throw const AppFailure(FailureKind.cancelled);
      await ref.read(accessTokenStoreProvider).write(token);
      ref.read(tokenHolderProvider).token = token;
      state = const AuthState(status: AuthStatus.signedIn);
      await refreshProfile();
    } on AppFailure catch (e) {
      if (!isCurrent()) return;
      state = AuthState(
        status: e.kind == FailureKind.cancelled ? AuthStatus.signedOut : AuthStatus.failed,
        failure: e.kind == FailureKind.cancelled ? null : e,
      );
    } catch (_) {
      if (!isCurrent()) return;
      state = const AuthState(
        status: AuthStatus.failed,
        failure: AppFailure(FailureKind.unknown),
      );
    }
  }

  /// Opens the GitHub device page in the browser (user taps the button).
  Future<bool> openVerificationPage() async {
    final uri = Uri.parse(state.deviceCode?.verificationUri ?? 'https://github.com/login/device');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void cancelSignIn() {
    _attemptSeq++;
    if (state.status == AuthStatus.signingIn) {
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  void markExpired() {
    if (state.status == AuthStatus.signedIn) {
      unawaited(_expire());
    }
  }

  Future<void> _expire() async {
    ref.read(tokenHolderProvider).token = null;
    await ref.read(accessTokenStoreProvider).clear();
    state = AuthState(
      status: AuthStatus.expired,
      user: state.user,
      failure: const AppFailure(FailureKind.unauthorized),
    );
  }

  Future<void> signOut() async {
    ref.read(tokenHolderProvider).token = null;
    await ref.read(accessTokenStoreProvider).clear();
    await ref.read(sharedPreferencesProvider).remove(_userKey);
    await ref.read(localSessionStoreProvider).clear();
    ref.read(sessionProvider.notifier).resetLocal();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  static const _userKey = 'auth.cached_user.v1';

  void _cacheUser(GitHubUser user) {
    unawaited(ref
        .read(sharedPreferencesProvider)
        .setString(_userKey, jsonEncode(user.toJson())));
  }

  GitHubUser? _cachedUser() {
    final raw = ref.read(sharedPreferencesProvider).getString(_userKey);
    if (raw == null) return null;
    try {
      return GitHubUser.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
