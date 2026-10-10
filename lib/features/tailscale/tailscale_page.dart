import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/security/redactor.dart';
import '../../core/theme/app_theme.dart';
import '../../models/runner_diagnostics.dart';
import '../../state/session_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Tailscale status for the active session, taken from the workflow's own markers.
///
/// The app never shows "connected" from a guess. It shows an IP only when the
/// workflow reported it AND proved TCP 3389 answers on that address.
class TailscalePage extends ConsumerWidget {
  const TailscalePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final session = ref.watch(sessionProvider);
    final diag = session.snapshot?.diagnostics ?? RunnerDiagnostics.empty;
    final status = diag.tailscaleStatus;
    final ip = diag.tailscaleIp;
    final verified = status == TailscaleStatus.verified;

    final (title, body, color, icon) = switch (status) {
      TailscaleStatus.verified => (
          s.t('ts_status_verified'),
          s.t('ts_verified_desc'),
          AppColors.success,
          Icons.verified_rounded,
        ),
      TailscaleStatus.missingSecret => (
          s.t('dash_ts_missing_secret'),
          s.t('ts_missing_desc'),
          AppColors.warning,
          Icons.key_off_rounded,
        ),
      TailscaleStatus.invalidSecret => (
          s.t('ts_status_invalid_secret'),
          s.t('ts_invalid_desc'),
          AppColors.danger,
          Icons.error_outline_rounded,
        ),
      TailscaleStatus.joinFailed => (
          s.t('ts_status_join_failed'),
          _joinFailedBody(s, diag),
          AppColors.danger,
          Icons.link_off_rounded,
        ),
      TailscaleStatus.rdpUnreachable => (
          s.t('ts_status_rdp_unreachable'),
          s.t('ts_rdp_unreachable_desc'),
          AppColors.warning,
          Icons.desktop_access_disabled_rounded,
        ),
      TailscaleStatus.requiresRdp => (
          s.t('ts_status_requires_rdp'),
          s.t('ts_requires_rdp_desc'),
          AppColors.warning,
          Icons.settings_remote_rounded,
        ),
      TailscaleStatus.notReported => (
          s.t('dash_ts_unknown'),
          session.active == null ? s.t('ts_no_session') : s.t('ts_not_reported_desc'),
          AppColors.textMuted,
          Icons.help_outline_rounded,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('ts_page_title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            GlassCard(
              glow: color,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title,
                          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(body, style: const TextStyle(color: AppColors.textMuted, height: 1.5)),
                  const SizedBox(height: 14),
                  Text(s.t('ts_ip_label'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: SelectableText(
                        verified && ip != null ? ip : s.t('ts_ip_not_verified'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                    ),
                    if (verified && ip != null)
                      IconButton(
                        tooltip: s.t('copy'),
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: ip));
                          if (context.mounted) showAppSnack(context, s.t('secrets_copied'));
                        },
                      ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: s.t('ts_connect'),
              icon: Icons.vpn_key_rounded,
              onPressed: () async {
                // Official Tailscale key page opens in the browser; the key is then saved in Secrets.
                await launchUrl(Uri.parse(AppConfig.tailscaleAdminKeysUrl),
                    mode: LaunchMode.externalApplication);
                if (context.mounted) context.push('/secrets');
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: session.active == null
                  ? null
                  : () => ref.read(sessionProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(s.t('ts_recheck')),
            ),
            const SizedBox(height: 16),
            SectionTitle(s.t('ts_steps_title')),
            GlassCard(
              child: Text(s.t('setup_ts_steps'),
                  style: const TextStyle(height: 1.6, color: AppColors.textMuted)),
            ),
            const SizedBox(height: 12),
            SectionTitle(s.t('ts_limits_title')),
            GlassCard(
              child: Text(s.t('ts_limits_body'),
                  style: const TextStyle(height: 1.6, color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains a failed join from the runner's own classification, then shows the redacted original error.
/// Only a category we actually observed is named; anything else says so and shows the raw line.
String _joinFailedBody(AppStrings s, RunnerDiagnostics diag) {
  final key = switch (diag.tailscaleFailure) {
    'invalid_cli_flags' => 'ts_fail_invalid_cli_flags',
    'expired_key' => 'ts_fail_expired_key',
    'revoked_or_used_key' => 'ts_fail_revoked_or_used_key',
    'invalid_key' => 'ts_fail_invalid_key',
    'daemon_not_running' => 'ts_fail_daemon',
    'network_or_control_plane' => 'ts_fail_network',
    'join_timeout' => 'ts_fail_timeout',
    _ => 'ts_fail_unknown',
  };
  final err = diag.tailscaleError;
  final detail = (err == null || err.isEmpty)
      ? ''
      : '\n\n${s.t('ts_error_label')}: ${SecretRedactor.redact(err)}';
  return '${s.t(key)}$detail';
}
