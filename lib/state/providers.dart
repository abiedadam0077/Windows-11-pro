import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../data/repositories/github_repository.dart';
import '../data/services/access_token_store.dart';
import '../data/services/github_api.dart';
import '../data/services/local_session_store.dart';
import '../data/services/notification_service.dart';
import '../data/services/oauth_service.dart';
import '../data/services/rdp_service.dart';
import '../models/github_models.dart';
import 'auth_state.dart';

/// Overridden in `main()` with the preloaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final accessTokenStoreProvider = Provider<AccessTokenStore>((ref) => AccessTokenStore());

final tokenHolderProvider = Provider<AccessTokenHolder>((ref) => AccessTokenHolder());

final localSessionStoreProvider = Provider<LocalSessionStore>(
  (ref) => LocalSessionStore(ref.watch(sharedPreferencesProvider)),
);

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

final rdpServiceProvider = Provider<RdpService>((ref) => RdpService());

final oauthServiceProvider = Provider<OAuthService>((ref) => OAuthService());

final githubApiProvider = Provider<GitHubApi>((ref) {
  final holder = ref.watch(tokenHolderProvider);
  return GitHubApi(
    tokenReader: () => holder.token,
    onUnauthorized: () => ref.read(authProvider.notifier).markExpired(),
  );
});

final githubRepositoryProvider = Provider<GitHubRepository>(
  (ref) => GitHubRepository(ref.watch(githubApiProvider)),
);

/// Repositories the signed-in user can access (cached until invalidated).
final repositoriesProvider = FutureProvider<List<RepoSummary>>((ref) async {
  final repos = await ref.watch(githubRepositoryProvider).repositories();
  repos.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
  return repos;
});

/// Readiness checks for the selected repository (workflow, permissions, secrets).
final repoReadinessProvider =
    FutureProvider.family<RepoReadiness, RepoSummary>((ref, repo) {
  final path = ref.watch(settingsProvider.select((s) => s.workflowPath));
  return ref.watch(githubRepositoryProvider).checkReadiness(repo, path);
});

/// Historical runs of the workflow in a repository ("owner/name").
final historyRunsProvider =
    FutureProvider.family<List<WorkflowRun>, String>((ref, fullName) {
  final parts = fullName.split('/');
  final path = ref.watch(settingsProvider.select((s) => s.workflowPath));
  return ref.watch(githubRepositoryProvider).historyRuns(
        owner: parts.first,
        repo: parts.length > 1 ? parts[1] : '',
        workflowPath: path.isEmpty ? AppConfig.defaultWorkflowPath : path,
      );
});

/// The bundled workflow file that WinPilot installs into repositories.
final workflowTemplateProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString(AppConfig.workflowTemplateAsset),
);

/// Ticks every second for elapsed-time displays.
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/// Re-exported for convenience in UI code.
final authStatusProvider = Provider<AuthStatus>((ref) => ref.watch(authProvider).status);
