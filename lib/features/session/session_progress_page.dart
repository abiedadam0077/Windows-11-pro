import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/github_models.dart';
import '../../models/runner_diagnostics.dart';
import '../../models/session_phase.dart';
import '../../state/providers.dart';
import '../../state/session_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Live view of one workflow run. Shows what GitHub and the runner report;
/// nothing here is simulated or estimated.
class SessionProgressPage extends ConsumerStatefulWidget {
  const SessionProgressPage({super.key, required this.runId});

  final int runId;

  @override
  ConsumerState<SessionProgressPage> createState() => _SessionProgressPageState();
}

class _SessionProgressPageState extends ConsumerState<SessionProgressPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelected());
  }

  void _ensureSelected() {
    if (!mounted) return;
    final st = ref.read(sessionProvider);
    if (st.active?.runId == widget.runId) return;
    for (final r in st.records) {
      if (r.runId == widget.runId) {
        ref.read(sessionProvider.notifier).selectRecord(r);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final st = ref.watch(sessionProvider);
    final active = st.active;
    final ctrl = ref.read(sessionProvider.notifier);

    if (active == null || active.runId != widget.runId) {
      return Scaffold(
        appBar: AppBar(title: Text(s.t('session_title'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: s.t('session_not_found'),
              action: OutlinedButton(
                onPressed: () => context.go('/home/sessions'),
                child: Text(s.t('nav_sessions')),
              ),
            ),
          ),
        ),
      );
    }

    final snap = st.snapshot;
    final diag = snap?.diagnostics ?? RunnerDiagnostics.empty;
    final phase = snap?.run.phase ?? active.phase;
    final steps = snap?.primaryJob?.steps ?? const <WorkflowStep>[];
    final ip = diag.tailscaleIp;
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final endsAt = diag.sessionEndsAt;
    final logsQuery = 'repo=${Uri.encodeComponent(active.repoFullName)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('session_run', {'n': '${active.runNumber ?? active.runId}'})),
        actions: [
          IconButton(
            tooltip: s.t('refresh'),
            onPressed: st.refreshing ? null : () => ctrl.refresh(),
            icon: st.refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: s.t('session_open_github'),
            onPressed: () => openExternal(context, Uri.parse(snap?.run.htmlUrl ?? active.htmlUrl ?? 'https://github.com')),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ctrl.refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            GlassCard(
              glow: phaseColor(phase),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(active.repoFullName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                    PhaseBadge(phase: phase),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '${active.request.windowsUser} · Windows 11 ARM64 · '
                    '${s.t('setup_minutes_value', {'m': '${active.request.sessionMinutes}'})}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 10),
                  InfoRow(label: s.t('session_started'), value: formatDateTime(active.startedAt)),
                  InfoRow(label: s.t('session_last_update'), value: formatTime(st.lastRefresh)),
                ],
              ),
            ),
            if (phase.isActive) ...[
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('session_timer_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (endsAt == null)
                      Text(s.t('session_timer_unknown'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted))
                    else ...[
                      Text(
                        now.isBefore(endsAt) ? formatDuration(endsAt.difference(now)) : s.t('session_timer_over'),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900, color: AppColors.cyan),
                      ),
                      Text(s.t('session_ends_at', {'time': formatTime(endsAt)}),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
            if (st.runUnavailable) ...[
              const SizedBox(height: 12),
              _Notice(text: s.t('session_run_unavailable'), color: AppColors.warning),
            ],
            if (st.failure != null) ...[
              const SizedBox(height: 12),
              ErrorPanel(failure: st.failure!, onRetry: () => ctrl.refresh()),
            ],
            _sectionTitle(context, s.t('session_steps_title')),
            GlassCard(
              child: steps.isEmpty
                  ? Text(s.t('session_steps_waiting'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted))
                  : Column(
                      children: [
                        for (final step in steps)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              Icon(phaseIcon(mapRunStatus(step.status, step.conclusion)),
                                  size: 18, color: phaseColor(mapRunStatus(step.status, step.conclusion))),
                              const SizedBox(width: 10),
                              Expanded(child: Text(step.name, overflow: TextOverflow.ellipsis)),
                              Text(s.t(mapRunStatus(step.status, step.conclusion).labelKey),
                                  style: Theme.of(context).textTheme.labelSmall),
                            ]),
                          ),
                      ],
                    ),
            ),
            _sectionTitle(context, s.t('session_readiness_title')),
            GlassCard(
              child: Column(
                children: [
                  InfoRow(label: s.t('session_os'), value: diag.osName ?? '—'),
                  InfoRow(
                    label: s.t('session_arch'),
                    value: diag.architecture ?? '—',
                    valueColor: diag.architecture == null
                        ? null
                        : diag.isArm64
                            ? AppColors.success
                            : AppColors.danger,
                  ),
                  InfoRow(label: s.t('session_runner'), value: diag.runnerName ?? '—'),
                  InfoRow(label: s.t('session_ts_state'), value: diag.tailscaleState ?? '—'),
                  InfoRow(label: s.t('session_ts_ip'), value: ip ?? '—', trailing: ip == null
                      ? null
                      : IconButton(
                          tooltip: s.t('copy'),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: ip));
                            if (context.mounted) showAppSnack(context, s.t('copied'));
                          },
                        )),
                  InfoRow(
                    label: s.t('session_rdp_declared'),
                    value: diag.rdpReady == null
                        ? s.t('session_rdp_unknown')
                        : diag.rdpReady!
                            ? s.t('session_rdp_declared_yes')
                            : s.t('session_rdp_declared_no'),
                    valueColor: diag.rdpReady == true ? AppColors.success : null,
                  ),
                  if (diag.rdpReason != null && diag.rdpReason!.isNotEmpty)
                    InfoRow(label: s.t('session_rdp_reason'), value: diag.rdpReason!),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(s.t('session_readiness_disclaimer'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                  ),
                ],
              ),
            ),
            _sectionTitle(context, s.t('session_probe_title')),
            GlassCard(
              glow: AppColors.violet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_probeText(s, st.rdpProbe, ip), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    OutlinedButton.icon(
                      onPressed: ip == null || st.rdpProbe == RdpProbeState.checking ? null : () => ctrl.probeRdp(),
                      icon: const Icon(Icons.network_check_rounded),
                      label: Text(s.t('session_probe_action')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/rdp'),
                      icon: const Icon(Icons.desktop_windows_rounded),
                      label: Text(s.t('session_rdp_guide')),
                    ),
                  ]),
                ],
              ),
            ),
            _sectionTitle(context, s.t('session_actions_title')),
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/session/${active.runId}/logs?$logsQuery'),
                icon: const Icon(Icons.terminal_rounded),
                label: Text(s.t('session_logs')),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/session/${active.runId}/artifacts?$logsQuery'),
                icon: const Icon(Icons.download_rounded),
                label: Text(s.t('session_artifacts')),
              ),
              if (phase.isActive)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: st.busy ? null : _cancel,
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: Text(s.t('session_cancel')),
                ),
              if (phase.isTerminal)
                GradientButton(
                  label: s.t('session_rerun'),
                  icon: Icons.replay_rounded,
                  loading: st.busy,
                  onPressed: st.busy ? null : _rerun,
                ),
            ]),
            if (phase.isTerminal) ...[
              const SizedBox(height: 10),
              _Notice(text: s.t('session_ended_note'), color: AppColors.warning),
            ],
            _sectionTitle(context, s.t('session_activity_title')),
            GlassCard(
              child: st.activity.isEmpty
                  ? Text(s.t('session_activity_empty'))
                  : Column(
                      children: [
                        for (final e in st.activity.take(30))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(formatTime(e.at), style: Theme.of(context).textTheme.labelSmall),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(s.t(e.key, {
                                    for (final kv in e.args.entries) kv.key: s.t(kv.value),
                                  })),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _Notice(text: s.t('limits_short'), color: AppColors.cyan),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.3)),
      );

  String _probeText(AppStrings s, RdpProbeState p, String? ip) {
    if (ip == null) return s.t('session_probe_no_ip');
    return switch (p) {
      RdpProbeState.idle => s.t('session_probe_idle'),
      RdpProbeState.checking => s.t('session_probe_checking'),
      RdpProbeState.reachable => s.t('session_probe_ok'),
      RdpProbeState.unreachable => s.t('session_probe_fail'),
    };
  }

  Future<void> _cancel() async {
    final s = context.s;
    final ok = await confirmDialog(
      context,
      title: s.t('session_cancel_title'),
      body: s.t('session_cancel_body'),
      confirmLabel: s.t('session_cancel'),
      destructive: true,
    );
    if (!ok) return;
    await ref.read(sessionProvider.notifier).cancelActive();
  }

  Future<void> _rerun() async {
    final before = ref.read(sessionProvider).active?.runId;
    await ref.read(sessionProvider.notifier).rerunActive();
    if (!mounted) return;
    final st = ref.read(sessionProvider);
    if (st.active != null && st.active!.runId != before) {
      context.go('/session/${st.active!.runId}');
    } else if (st.failure != null) {
      showAppSnack(context, context.s.t(st.failure!.titleKey));
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(text),
      );
}
