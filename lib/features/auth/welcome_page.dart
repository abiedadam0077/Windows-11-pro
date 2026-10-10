import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Login screen. Uses the GitHub OAuth web flow (PKCE) in the system browser.
/// WinPilot never shows a GitHub password field.
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final signingIn = auth.status == AuthStatus.signingIn;
    final failure = auth.failure;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          children: [
            Center(child: BrandLogo(size: 92, animate: true)),
            const SizedBox(height: 24),
            Text(
              s.t('welcome_title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, height: 1.25),
            ),
            const SizedBox(height: 12),
            Text(
              s.t('welcome_desc'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 22),
            GlassCard(
              glow: AppColors.violet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('welcome_how_title'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  _step(context, Icons.lock_outline_rounded, s.t('welcome_step1')),
                  _step(context, Icons.folder_outlined, s.t('welcome_step2')),
                  _step(context, Icons.play_circle_outline_rounded, s.t('welcome_step3')),
                  _step(context, Icons.vpn_lock_rounded, s.t('welcome_step4')),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (failure != null) ...[
              if (failure.kind == FailureKind.notConfigured)
                _Notice(text: s.t('welcome_not_configured'), color: AppColors.warning)
              else
                ErrorPanel(failure: failure),
              const SizedBox(height: 14),
            ],
            if (signingIn) ...[
              _Notice(text: s.t('welcome_connecting'), color: AppColors.electricBlue),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.read(authProvider.notifier).cancelSignIn(),
                child: Text(s.t('welcome_cancel_login')),
              ),
            ] else
              GradientButton(
                label: s.t('welcome_github_button'),
                icon: Icons.login_rounded,
                onPressed: () async {
                  await ref.read(authProvider.notifier).signIn();
                  if (!context.mounted) return;
                  final status = ref.read(authProvider).status;
                  if (status == AuthStatus.signedIn) context.go('/home/dashboard');
                },
              ),
            const SizedBox(height: 14),
            if (failure?.kind == FailureKind.notConfigured)
              OutlinedButton(
                onPressed: () => context.go('/home/settings'),
                child: Text(s.t('settings_client_id')),
              ),
            const SizedBox(height: 18),
            Text(
              s.t('welcome_secure_note'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              children: [
                Text(s.t('welcome_terms_note'), style: theme.textTheme.bodySmall),
                TextButton(
                  onPressed: () => context.push('/legal/terms'),
                  child: Text(s.t('terms')),
                ),
                Text('·', style: theme.textTheme.bodySmall),
                TextButton(
                  onPressed: () => context.push('/legal/privacy'),
                  child: Text(s.t('privacy')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.electricBlue.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppColors.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
