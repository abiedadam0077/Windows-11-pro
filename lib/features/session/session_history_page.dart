import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/session_phase.dart';
import '../../state/session_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Sessions started from this device, newest first. Stored locally only.
class SessionHistoryPage extends ConsumerWidget {
  const SessionHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final st = ref.watch(sessionProvider);
    final records = st.records;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('history_title')),
        actions: [
          if (records.isNotEmpty)
            IconButton(
              tooltip: s.t('history_clear'),
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: s.t('history_clear_title'),
                  body: s.t('history_clear_body'),
                  confirmLabel: s.t('history_clear'),
                  destructive: true,
                );
                if (ok) ref.read(sessionProvider.notifier).clearHistory();
              },
            ),
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyState(
                  icon: Icons.history_rounded,
                  title: s.t('history_empty'),
                  body: s.t('history_empty_body'),
                  action: FilledButton.icon(
                    onPressed: () => context.push('/setup'),
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: Text(s.t('dash_start_session')),
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final rec = records[i];
                final phase = rec.phase;
                return GlassCard(
                  glow: phase.isActive ? AppColors.cyan : null,
                  onTap: () {
                    ref.read(sessionProvider.notifier).selectRecord(rec);
                    context.push('/session/${rec.runId}');
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(rec.repoFullName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        PhaseBadge(phase: phase),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        '${s.t('session_run', {'n': '${rec.runNumber ?? rec.runId}'})} · '
                        '${formatDateTime(rec.startedAt)} · ${rec.request.windowsUser}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
