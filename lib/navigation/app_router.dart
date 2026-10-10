import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/artifacts/artifacts_page.dart';
import '../features/auth/account_page.dart';
import '../features/auth/welcome_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/home/home_shell.dart';
import '../features/about/about_page.dart';
import '../features/legal/legal_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/rdp/rdp_guide_page.dart';
import '../features/repos/repo_picker_page.dart';
import '../features/session/log_viewer_page.dart';
import '../features/session/session_history_page.dart';
import '../features/session/session_progress_page.dart';
import '../features/secrets/secrets_page.dart';
import '../features/tailscale/tailscale_page.dart';
import '../features/settings/settings_page.dart';
import '../features/setup/setup_wizard_page.dart';
import '../features/splash/splash_page.dart';
import '../state/auth_state.dart';
import '../state/settings_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider.select((a) => a.status), (_, __) => refresh.value++);
  ref.listen(settingsProvider.select((s) => s.onboardingDone), (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == '/splash') return null;
      final settings = ref.read(settingsProvider);
      if (!settings.onboardingDone) {
        return loc == '/onboarding' ? null : '/onboarding';
      }
      final status = ref.read(authProvider).status;
      final signedIn = status == AuthStatus.signedIn || status == AuthStatus.expired;
      final isPublic = loc == '/welcome' || loc == '/onboarding' ||
          loc == '/about' || loc.startsWith('/legal');
      if (!signedIn && !isPublic) return '/welcome';
      if (signedIn && loc == '/welcome') return '/home/dashboard';
      if (status == AuthStatus.unknown && loc != '/splash') return '/splash';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingPage()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomePage()),
      GoRoute(
        path: '/legal/:type',
        builder: (context, state) => LegalPage(type: state.pathParameters['type'] ?? 'privacy'),
      ),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/home', redirect: (_, __) => '/home/dashboard'),
          GoRoute(path: '/home/dashboard', builder: (context, state) => const DashboardPage()),
          GoRoute(path: '/home/sessions', builder: (context, state) => const SessionHistoryPage()),
          GoRoute(path: '/home/settings', builder: (context, state) => const SettingsPage()),
        ],
      ),
      GoRoute(path: '/account', builder: (context, state) => const AccountPage()),
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
      GoRoute(path: '/repos', builder: (context, state) => const RepoPickerPage()),
      GoRoute(path: '/setup', builder: (context, state) => const SetupWizardPage()),
      GoRoute(path: '/rdp', builder: (context, state) => const RdpGuidePage()),
      GoRoute(path: '/secrets', builder: (context, state) => const SecretsPage()),
      GoRoute(path: '/tailscale', builder: (context, state) => const TailscalePage()),
      GoRoute(
        path: '/session/:runId',
        builder: (context, state) => SessionProgressPage(
          runId: int.tryParse(state.pathParameters['runId'] ?? '') ?? -1,
        ),
      ),
      GoRoute(
        path: '/session/:runId/logs',
        builder: (context, state) => LogViewerPage(
          runId: int.tryParse(state.pathParameters['runId'] ?? '') ?? -1,
          repoFullName: state.uri.queryParameters['repo'] ?? '',
        ),
      ),
      GoRoute(
        path: '/session/:runId/artifacts',
        builder: (context, state) => ArtifactsPage(
          runId: int.tryParse(state.pathParameters['runId'] ?? '') ?? -1,
          repoFullName: state.uri.queryParameters['repo'] ?? '',
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text(state.error?.toString() ?? 'Route error')),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
