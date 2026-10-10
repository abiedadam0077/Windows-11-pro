import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final (label, color) = switch (auth.status) {
      AuthStatus.signedIn when auth.offline => (s.t('account_status_offline'), AppColors.warning),
      AuthStatus.signedIn => (s.t('account_status_connected'), AppColors.success),
      AuthStatus.expired => (s.t('account_status_expired'), AppColors.danger),
      _ => (s.t('account_status_signed_out'), AppColors.textMuted),
    };

    return Scaffold(
      appBar: AppBar(title: Text(s.t('account_title'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          GlassCard(
            glow: AppColors.electricBlue,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.violet.withValues(alpha: 0.3),
                  backgroundImage:
                      user?.avatarUrl == null ? null : NetworkImage(user!.avatarUrl!),
                  child: user?.avatarUrl == null
                      ? const Icon(Icons.person_rounded, size: 34, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name?.isNotEmpty == true ? user!.name! : (user?.login ?? '—'),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      if (user != null)
                        Text('@${user.login}', style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      StatusChip(label: label, color: color),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (auth.status == AuthStatus.expired) ...[
            const SizedBox(height: 14),
            _Notice(text: s.t('account_reconnect_hint'), color: AppColors.danger),
          ],
          const SizedBox(height: 8),
          SectionTitle(s.t('account_scopes_title')),
          GlassCard(
            child: Column(
              children: [
                InfoRow(
                  label: s.t('account_scope_repo'),
                  value: auth.hasRepoScope ? s.t('account_scope_ok') : s.t('account_scope_missing'),
                  valueColor: auth.hasRepoScope ? AppColors.success : AppColors.warning,
                ),
                const Divider(),
                InfoRow(
                  label: s.t('account_scope_workflow'),
                  value: auth.canWriteWorkflows ? s.t('account_scope_ok') : s.t('account_scope_missing'),
                  valueColor: auth.canWriteWorkflows ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    s.t('account_permissions_why'),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.5),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('OAuth device flow · ${AppConfig.oauthScopes}',
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (auth.status == AuthStatus.expired || auth.status == AuthStatus.signedOut || auth.status == AuthStatus.failed)
            GradientButton(
              label: s.t('reconnect'),
              icon: Icons.refresh_rounded,
              onPressed: () async {
                await ref.read(authProvider.notifier).signIn();
                if (context.mounted && ref.read(authProvider).status == AuthStatus.signedIn) {
                  showAppSnack(context, s.t('settings_saved'));
                }
              },
            )
          else
            OutlinedButton.icon(
              onPressed: () => ref.read(authProvider.notifier).refreshProfile(),
              icon: const Icon(Icons.sync_rounded),
              label: Text(s.t('refresh')),
            ),
          const SizedBox(height: 12),
          if (user?.htmlUrl != null)
            OutlinedButton.icon(
              onPressed: () => openExternal(context, Uri.parse(user!.htmlUrl!)),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(s.t('account_profile_link')),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: s.t('account_sign_out_title'),
                body: s.t('account_sign_out_body'),
                destructive: true,
              );
              if (!ok) return;
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) context.go('/welcome');
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(s.t('settings_sign_out')),
          ),
        ],
      ),
    );
  }
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
        child: Text(text),
      );
}
