import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../models/runner_diagnostics.dart';
import '../../models/session_models.dart';
import '../../models/session_phase.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
import '../../state/session_state.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Main control panel: active session, verified runner facts, Tailscale/RDP
/// readiness, recent activity and actions. Every value shown comes from GitHub,
/// the runner's own diagnostics lines, or an actual TCP probe.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final auth = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final active = session.active;
    final diag = session.snapshot?.diagnostics ?? RunnerDiagnostics.empty;
    final name = auth.user?.name?.isNotEmpty == true ? auth.user!.name! : (auth.user?.login ?? '');

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(sessionProvider.notifier).refresh(silent: true);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 110),
        children: [
          _Header(
            greeting: name.isEmpty ? s.t('dash_greeting_anon') : s.t('dash_greeting', {'name': name}),
            avatarUrl: auth.user?.avatarUrl,
            lastUpdate: session.lastRefresh,
          ),
          const SizedBox(height: 16),
          if (active == null)
            _NoSessionCard(onStart: () => context.push('/setup'))
          else
            _ActiveCard(active: active, diag: diag, now: now, session: session),
          if (active != null && active.phase.isTerminal) ...[
            const SizedBox(height: 14),
            _EndedCard(active: active, session: session),
          ],
          if (session.failure != null && !session.runUnavailable) ...[
            const SizedBox(height: 14),
            ErrorPanel(
              failure: session.failure!,
              onRetry: () => ref.read(sessionProvider.notifier).refresh(),
            ),
          ],
          SectionTitle(s.t('dash_card_github')),
          _StatusGrid(children: _statusCards(context, ref, auth, settings, active, diag, session, now)),
          const SizedBox(height: 4),
          SectionTitle(s.t('dash_actions_title')),
          _ActionsWrap(active: active, session: session),
          SectionTitle(s.t('dash_activity_title')),
          _ActivityList(session: session),
          const SizedBox(height: 14),
          GlassCard(
            glow: AppColors.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.t('dash_ephemeral_warning'))),
                ]),
                const SizedBox(height: 10),
                Text(s.t('dash_no_resources'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _statusCards(
    BuildContext context,
    WidgetRef ref,
    AuthState auth,
    AppSettings settings,
    SessionRecord? active,
    RunnerDiagnostics diag,
    SessionState session,
    DateTime now,
  ) {
    final s = context.s;
    final repoName = active?.repoFullName ?? settings.defaultRepo;

    final githubText = switch (auth.status) {
      AuthStatus.signedIn when auth.user != null => s.t('dash_github_connected', {'login': auth.user!.login}),
      AuthStatus.signedIn => s.t('dash_github_offline'),
      AuthStatus.expired => s.t('dash_github_expired'),
      _ => s.t('dash_github_none'),
    };
    final githubColor = auth.status == AuthStatus.signedIn
        ? AppColors.success
        : auth.status == AuthStatus.expired
            ? AppColors.danger
            : AppColors.textMuted;

    final verified = diag.hasAnyData && diag.osName != null;
    final tsState = diag.tailscaleState;
    final (tsText, tsColor) = switch (tsState) {
      null => (s.t('dash_ts_unknown'), AppColors.textMuted),
      'Running' => (s.t('dash_ts_running'), AppColors.success),
      'NeedsLogin' => (s.t('dash_ts_needs_login'), AppColors.warning),
      'disabled' => (s.t('dash_ts_disabled'), AppColors.textMuted),
      'missing_secret' => (s.t('dash_ts_missing_secret'), AppColors.warning),
      'install_failed' => (s.t('dash_ts_install_failed'), AppColors.danger),
      final other => (other, AppColors.warning),
    };

    final ip = diag.tailscaleIp;
    final ipValid = ip != null && Validators.isValidIpv4(ip);
    final ipText = ip == null
        ? s.t('dash_ip_not_reported')
        : (ipValid && Validators.isTailscaleIpv4(ip) ? ip : s.t('dash_ip_invalid'));
    final ipColor = ipValid && Validators.isTailscaleIpv4(ip) ? AppColors.success : AppColors.textMuted;

    final rdpRequested = active?.request.enableRdp ?? false;
    final probeText = switch (session.rdpProbe) {
      RdpProbeState.idle => s.t('dash_rdp_probe_idle'),
      RdpProbeState.checking => s.t('dash_rdp_probe_checking'),
      RdpProbeState.reachable => s.t('dash_rdp_probe_ok'),
      RdpProbeState.unreachable => s.t('dash_rdp_probe_fail'),
    };
    final rdpText = diag.rdpReady == true
        ? s.t('dash_rdp_declared')
        : rdpRequested
            ? (diag.rdpReason == 'edition_unsupported'
                ? s.t('dash_rdp_reason_edition')
                : s.t('dash_rdp_not_declared'))
            : s.t('dash_rdp_unknown');
    final rdpColor = diag.rdpReady == true ? AppColors.success : AppColors.textMuted;

    final started = active?.startedAt;
    final elapsed = started == null ? null : now.difference(started);
    final endsAt = diag.sessionEndsAt;
    final remaining = endsAt?.difference(now);

    return [
      _StatusTile(
        icon: Icons.account_circle_rounded,
        label: s.t('dash_card_github'),
        value: githubText,
        color: githubColor,
        onTap: () => context.push('/account'),
      ),
      _StatusTile(
        icon: Icons.folder_rounded,
        label: s.t('dash_card_repo'),
        value: repoName ?? s.t('dash_repo_none'),
        color: repoName == null ? AppColors.textMuted : AppColors.cyan,
        onTap: () => context.push('/repos'),
      ),
      _StatusTile(
        icon: Icons.account_tree_rounded,
        label: s.t('dash_card_workflow'),
        value: settings.workflowPath,
        color: AppColors.violet,
        onTap: () => context.go('/home/settings'),
      ),
      _StatusTile(
        icon: Icons.desktop_windows_rounded,
        label: s.t('dash_card_windows'),
        value: verified
            ? s.t('dash_windows_verified', {'os': diag.osName ?? ''})
            : s.t('dash_windows_not_verified'),
        color: verified ? AppColors.success : AppColors.textMuted,
      ),
      _StatusTile(
        icon: Icons.memory_rounded,
        label: s.t('dash_card_arch'),
        value: diag.isArm64 ? s.t('dash_arch_verified') : s.t('dash_arch_unknown'),
        color: diag.isArm64 ? AppColors.success : AppColors.textMuted,
      ),
      _StatusTile(
        icon: Icons.schedule_rounded,
        label: s.t('dash_card_started'),
        value: started == null ? '—' : formatDateTime(started),
        color: AppColors.cyan,
      ),
      _StatusTile(
        icon: Icons.timer_outlined,
        label: s.t('dash_card_elapsed'),
        value: elapsed == null ? '—' : formatDuration(elapsed),
        color: AppColors.electricBlue,
      ),
      _StatusTile(
        icon: Icons.hourglass_bottom_rounded,
        label: s.t('dash_card_remaining'),
        value: remaining == null
            ? s.t('dash_remaining_unknown')
            : formatDuration(remaining.isNegative ? Duration.zero : remaining),
        color: remaining != null && remaining <= AppConfig.expiryWarning ? AppColors.warning : AppColors.textMuted,
      ),
      _StatusTile(
        icon: Icons.vpn_lock_rounded,
        label: s.t('dash_card_tailscale'),
        value: tsText,
        color: tsColor,
        onTap: () => context.push('/rdp'),
      ),
      _StatusTile(
        icon: Icons.lan_rounded,
        label: s.t('dash_card_ip'),
        value: ipText,
        color: ipColor,
        trailing: ipValid && Validators.isTailscaleIpv4(ip)
            ? IconButton(
                tooltip: s.t('copy'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _copy(context, ip),
              )
            : null,
      ),
      _StatusTile(
        icon: Icons.settings_remote_rounded,
        label: s.t('dash_card_rdp'),
        value: '$rdpText\n$probeText',
        color: rdpColor,
        onTap: () => context.push('/rdp'),
      ),
    ];
  }

  static Future<void> _copy(BuildContext context, String text) async {
    final s = context.s;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showAppSnack(context, s.t('copied'));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.avatarUrl, required this.lastUpdate});

  final String greeting;
  final String? avatarUrl;
  final DateTime? lastUpdate;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Row(
      children: [
        const BrandLogo(size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              Text(
                lastUpdate == null
                    ? s.t('session_refresh_hint')
                    : s.t('dash_last_update', {'time': formatTime(lastUpdate)}),
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/account'),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.violet.withValues(alpha: 0.3),
            backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
            child: avatarUrl == null ? const Icon(Icons.person_rounded, color: Colors.white) : null,
          ),
        ),
      ],
    );
  }
}

class _NoSessionCard extends StatelessWidget {
  const _NoSessionCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return GlassCard(
      glow: AppColors.electricBlue,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.rocket_launch_rounded, color: AppColors.cyan, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.t('dash_no_session_title'),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(s.t('dash_no_session_body'),
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted, height: 1.5)),
          const SizedBox(height: 18),
          GradientButton(label: s.t('dash_new_session'), icon: Icons.add_rounded, onPressed: onStart),
        ],
      ),
    );
  }
}

class _ActiveCard extends ConsumerWidget {
  const _ActiveCard({required this.active, required this.diag, required this.now, required this.session});

  final SessionRecord active;
  final RunnerDiagnostics diag;
  final DateTime now;
  final SessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final theme = Theme.of(context);
    final phase = active.phase;
    final color = phaseColor(phase);
    final endsAt = diag.sessionEndsAt;
    final expiringSoon = endsAt != null && phase == SessionPhase.running && endsAt.difference(now) <= AppConfig.expiryWarning;
    return GlassCard(
      glow: color,
      padding: const EdgeInsets.all(20),
      onTap: () => context.push('/session/${active.runId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhaseBadge(phase: phase),
              const Spacer(),
              Text(s.t('session_run', {'n': '${active.runNumber ?? active.runId}'}),
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 14),
          Text(active.repoFullName,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            '${active.request.windowsUser} · Windows 11 ARM64 · ${s.t('setup_minutes_value', {'m': '${active.request.sessionMinutes}'})}',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 6,
              color: color,
              value: phase.isActive ? null : 1,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          if (expiringSoon) ...[
            const SizedBox(height: 10),
            Text(s.t('dash_expiry_soon'), style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
          ],
          if (session.runUnavailable) ...[
            const SizedBox(height: 10),
            Text(s.t('dash_run_unavailable'), style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.t('session_started')}: ${formatTime(active.startedAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '${s.t('session_updated')}: ${formatTime(session.lastRefresh)}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => context.push('/session/${active.runId}'),
              icon: const Icon(Icons.chevron_right_rounded),
              label: Text(s.t('session_title')),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.active, required this.session});

  final SessionRecord active;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final reason = switch (active.phase) {
      SessionPhase.failed || SessionPhase.timedOut => s.t('dash_ended_failed'),
      SessionPhase.cancelled => s.t('dash_ended_cancelled'),
      SessionPhase.succeeded => s.t('dash_ended_succeeded'),
      _ => s.t('dash_ended_other'),
    };
    return GlassCard(
      glow: phaseColor(active.phase),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            PhaseBadge(phase: active.phase),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.t('dash_ended_title'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(reason),
          const SizedBox(height: 6),
          Text(s.t('dash_ended_body'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          InfoRow(label: s.t('history_started'), value: formatDateTime(active.startedAt)),
          InfoRow(
            label: s.t('history_duration'),
            value: active.endedAt == null
                ? '—'
                : formatDuration(active.endedAt!.difference(active.startedAt)),
          ),
          const SizedBox(height: 6),
          Text(s.t('dash_ended_next'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/session/${active.runId}/logs?repo=${Uri.encodeComponent(active.repoFullName)}'),
                  child: Text(s.t('session_view_logs')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(label: s.t('dash_new_session'), onPressed: () => context.push('/setup')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final c in children) SizedBox(width: width, child: c)],
          );
        },
      );
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _ActionsWrap extends ConsumerWidget {
  const _ActionsWrap({required this.active, required this.session});

  final SessionRecord? active;
  final SessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final a = active;
    final terminal = a == null || a.phase.isTerminal;
    final rdpReady = session.snapshot?.diagnostics.rdpReady == true;
    final items = <Widget>[
      if (a != null)
        _ActionChip(
          icon: Icons.settings_remote_rounded,
          label: s.t('dash_action_rdp'),
          onTap: () => context.push('/rdp'),
          enabled: rdpReady,
        ),
      _ActionChip(
        icon: Icons.refresh_rounded,
        label: s.t('dash_action_refresh'),
        onTap: a == null ? null : () => ref.read(sessionProvider.notifier).refresh(),
        enabled: a != null,
      ),
      _ActionChip(
        icon: Icons.terminal_rounded,
        label: s.t('dash_action_logs'),
        onTap: a == null
            ? null
            : () => context.push('/session/${a.runId}/logs?repo=${Uri.encodeComponent(a.repoFullName)}'),
        enabled: a != null,
      ),
      _ActionChip(
        icon: Icons.replay_rounded,
        label: s.t('dash_action_rerun'),
        onTap: a == null || !terminal ? null : () => _rerun(context, ref),
        enabled: a != null && terminal,
      ),
      _ActionChip(
        icon: Icons.stop_circle_outlined,
        label: s.t('dash_action_cancel'),
        danger: true,
        onTap: a == null || terminal ? null : () => _cancel(context, ref),
        enabled: a != null && !terminal && !session.busy,
      ),
      _ActionChip(
        icon: Icons.manage_history_rounded,
        label: s.t('dash_action_sessions'),
        onTap: () => context.go('/home/sessions'),
        enabled: true,
      ),
      _ActionChip(
        icon: Icons.download_for_offline_rounded,
        label: s.t('dash_action_artifacts'),
        onTap: a == null
            ? null
            : () => context.push('/session/${a.runId}/artifacts?repo=${Uri.encodeComponent(a.repoFullName)}'),
        enabled: a != null,
      ),
    ];
    return Wrap(spacing: 10, runSpacing: 10, children: items);
  }

  Future<void> _rerun(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final ok = await confirmDialog(
      context,
      title: s.t('session_rerun'),
      body: s.t('session_terminal_note'),
    );
    if (!ok) return;
    final started = await ref.read(sessionProvider.notifier).startSession(
          repoFullName: active!.repoFullName,
          branch: active!.branch,
          request: active!.request,
        );
    if (context.mounted && started) {
      final id = ref.read(sessionProvider).active?.runId;
      if (id != null) context.push('/session/$id');
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final s = context.s;
    final ok = await confirmDialog(
      context,
      title: s.t('session_cancel_title'),
      body: s.t('session_cancel_body'),
      destructive: true,
    );
    if (ok) await ref.read(sessionProvider.notifier).cancelActive();
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.electricBlue;
    final active = enabled && onTap != null;
    return Opacity(
      opacity: active ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: active ? onTap : null,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: danger ? AppColors.danger : AppColors.cyan),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final items = session.activity.take(8).toList();
    if (items.isEmpty) {
      return GlassCard(child: Text(s.t('dash_activity_empty')));
    }
    return GlassCard(
      child: Column(
        children: [
          for (final e in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon(e.kind), size: 16, color: _color(e.kind)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_text(s, e))),
                  Text(formatTime(e.at),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _text(AppStrings s, ActivityEntry e) => s.t(
        e.key,
        {for (final kv in e.args.entries) kv.key: s.t(kv.value)},
      );

  IconData _icon(ActivityKind k) => switch (k) {
        ActivityKind.success => Icons.check_circle_outline_rounded,
        ActivityKind.warning => Icons.warning_amber_rounded,
        ActivityKind.error => Icons.error_outline_rounded,
        ActivityKind.info => Icons.circle_outlined,
      };

  Color _color(ActivityKind k) => switch (k) {
        ActivityKind.success => AppColors.success,
        ActivityKind.warning => AppColors.warning,
        ActivityKind.error => AppColors.danger,
        ActivityKind.info => AppColors.cyan,
      };
}
