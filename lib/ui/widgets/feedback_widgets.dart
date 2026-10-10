import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/security/redactor.dart';
import '../../core/theme/app_theme.dart';
import '../../models/session_phase.dart';
import '../../models/session_stage.dart';
import 'brand_widgets.dart';

Color phaseColor(SessionPhase phase) => switch (phase) {
      SessionPhase.queued => AppColors.warning,
      SessionPhase.running => AppColors.electricBlue,
      SessionPhase.succeeded => AppColors.success,
      SessionPhase.failed || SessionPhase.timedOut => AppColors.danger,
      SessionPhase.cancelled || SessionPhase.skipped || SessionPhase.unknown => AppColors.textMuted,
    };

IconData phaseIcon(SessionPhase phase) => switch (phase) {
      SessionPhase.queued => Icons.hourglass_top_rounded,
      SessionPhase.running => Icons.autorenew_rounded,
      SessionPhase.succeeded => Icons.check_circle_rounded,
      SessionPhase.failed || SessionPhase.timedOut => Icons.error_rounded,
      SessionPhase.cancelled => Icons.cancel_rounded,
      SessionPhase.skipped || SessionPhase.unknown => Icons.help_outline_rounded,
    };

class PhaseBadge extends StatelessWidget {
  const PhaseBadge({super.key, required this.phase});

  final SessionPhase phase;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final color = phaseColor(phase);
    return StatusChip(label: s.t(phase.labelKey), color: color, icon: phaseIcon(phase));
  }
}

/// Session stage as the user sees it (Queued, Starting, Waiting for Windows, Running, ...).
class SessionStageBadge extends StatelessWidget {
  const SessionStageBadge({super.key, required this.stage});

  final SessionStage stage;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final color = switch (stage) {
      SessionStage.queued => AppColors.warning,
      SessionStage.starting || SessionStage.waitingForWindows => AppColors.warning,
      SessionStage.running || SessionStage.savingBackup => AppColors.electricBlue,
      SessionStage.completed => AppColors.success,
      SessionStage.failed => AppColors.danger,
    };
    final icon = switch (stage) {
      SessionStage.queued => Icons.hourglass_top_rounded,
      SessionStage.starting || SessionStage.waitingForWindows => Icons.pending_rounded,
      SessionStage.running => Icons.desktop_windows_rounded,
      SessionStage.savingBackup => Icons.backup_rounded,
      SessionStage.completed => Icons.check_circle_rounded,
      SessionStage.failed => Icons.error_rounded,
    };
    return StatusChip(label: s.t(stage.labelKey), color: color, icon: icon);
  }
}

/// Shows a typed failure with a plain explanation, a fix hint and masked details.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.failure, this.onRetry});

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final detail = failure.detail == null ? null : SecretRedactor.redact(failure.detail!);
    final resetHint = failure.resetAt == null
        ? null
        : '${failure.resetAt!.toLocal().hour.toString().padLeft(2, '0')}:${failure.resetAt!.toLocal().minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.t(failure.titleKey),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(s.t(failure.hintKey), style: theme.textTheme.bodyMedium),
          if (resetHint != null) ...[
            const SizedBox(height: 6),
            Text('≈ $resetHint', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          ],
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(s.t('err_details'), style: theme.textTheme.bodySmall),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SelectableText(detail,
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                ),
              ],
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(s.t('retry')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens an external URL (browser, RDP client, Play Store) and reports failures.
Future<void> openExternal(BuildContext context, Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = context.s.t('err_unsupported_title');
  try {
    final ok = await launchUrl(uri, mode: mode);
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(message)));
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Simple confirm dialog returning true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final s = context.s;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.t('cancel'))),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel ?? s.t('confirm')),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Full-page placeholder with brand logo and a message.
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 16),
            Text(message ?? context.s.t('loading')),
          ],
        ),
      );
}
