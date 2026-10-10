import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_failure.dart';
import '../models/github_models.dart';
import '../data/services/oauth_service.dart';
import 'providers.dart';
import 'session_state.dart';

enum AuthStatus { unknown, signedOut, signingIn, signedIn, expired, failed }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.scopes = const [],
    this.failure,
    this.offline = false,
  });

  final AuthStatus status;
  final GitHubUser? user;
  final List<String> scopes;
  final AppFailure? failure;

  /// True when the profile could not be refreshed due to connectivity.
  final bool offline;

  bool get isSignedIn => status == AuthStatus.signedIn || status == AuthStatus.expired;

  /// Classic OAuth scopes: `workflow` is needed to write workflow files.
  bool get canWriteWorkflows => scopes.contains('workflow');

  bool get hasRepoScope => scopes.contains('repo');
}

class AuthController extends Notifier<AuthState> {
  final AppLinks _appLinks = AppLinks();
  Completer<Uri>? _pendingCallback;

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

  /// OAuth Authorization Code flow with PKCE, opened in the system browser.
  /// The redirect comes back through the `winpilot://oauth/callback` deep link.
  Future<void> signIn() async {
    final clientId = ref.read(settingsProvider).effectiveClientId;
    if (clientId.isEmpty) {
      state = const AuthState(
        status: AuthStatus.failed,
        failure: AppFailure(FailureKind.notConfigured),
      );
      return;
    }

    final attempt = OAuthAttempt.create();
    final callback = Completer<Uri>();
    _pendingCallback = callback;
    final sub = _appLinks.uriLinkStream.listen(
      (uri) {
        if (uri.scheme == AppConfig.oauthCallbackScheme &&
            uri.host == 'oauth' &&
            !callback.isCompleted) {
          callback.complete(uri);
        }
      },
      onError: (Object _) {
        if (!callback.isCompleted) {
          callback.completeError(const AppFailure(FailureKind.unknown));
        }
      },
    );

    state = const AuthState(status: AuthStatus.signingIn);
    try {
      final opened = await launchUrl(
        attempt.authorizeUri(clientId),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw const AppFailure(FailureKind.unsupported, detail: 'no browser');

      final uri = await callback.future.timeout(const Duration(minutes: 5));
      final error = uri.queryParameters['error'];
      if (error != null) {
        throw AppFailure(
          error == 'access_denied' ? FailureKind.cancelled : FailureKind.unauthorized,
          detail: uri.queryParameters['error_description'] ?? error,
        );
      }
      if (uri.queryParameters['state'] != attempt.state) {
        throw const AppFailure(FailureKind.unauthorized, detail: 'state mismatch');
      }
      final code = uri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const AppFailure(FailureKind.unauthorized, detail: 'missing authorization code');
      }

      final token = await ref.read(oauthServiceProvider).exchangeCode(
            clientId: clientId,
            code: code,
            verifier: attempt.verifier,
          );
      await ref.read(accessTokenStoreProvider).write(token);
      ref.read(tokenHolderProvider).token = token;
      state = const AuthState(status: AuthStatus.signedIn);
      await refreshProfile();
    } on TimeoutException {
      state = const AuthState(
        status: AuthStatus.failed,
        failure: AppFailure(FailureKind.timeout),
      );
    } on AppFailure catch (e) {
      state = AuthState(
        status: e.kind == FailureKind.cancelled ? AuthStatus.signedOut : AuthStatus.failed,
        failure: e.kind == FailureKind.cancelled ? null : e,
      );
    } catch (_) {
      state = const AuthState(
        status: AuthStatus.failed,
        failure: AppFailure(FailureKind.unknown),
      );
    } finally {
      await sub.cancel();
      _pendingCallback = null;
    }
  }

  void cancelSignIn() {
    final pending = _pendingCallback;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const AppFailure(FailureKind.cancelled));
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
