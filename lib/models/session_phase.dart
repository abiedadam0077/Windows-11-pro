/// Application-level state of a workflow run, derived from GitHub's
/// `status` and `conclusion` fields.
enum SessionPhase { queued, running, succeeded, failed, cancelled, timedOut, skipped, unknown }

extension SessionPhaseX on SessionPhase {
  /// True when GitHub will not change this run's state anymore.
  bool get isTerminal => switch (this) {
        SessionPhase.succeeded ||
        SessionPhase.failed ||
        SessionPhase.cancelled ||
        SessionPhase.timedOut ||
        SessionPhase.skipped =>
          true,
        _ => false,
      };

  bool get isActive => this == SessionPhase.queued || this == SessionPhase.running;

  String get labelKey => switch (this) {
        SessionPhase.queued => 'phase_queued',
        SessionPhase.running => 'phase_running',
        SessionPhase.succeeded => 'phase_succeeded',
        SessionPhase.failed => 'phase_failed',
        SessionPhase.cancelled => 'phase_cancelled',
        SessionPhase.timedOut => 'phase_timed_out',
        SessionPhase.skipped => 'phase_skipped',
        SessionPhase.unknown => 'phase_unknown',
      };
}

/// Maps GitHub Actions run `status` / `conclusion` values to [SessionPhase].
/// See https://docs.github.com/rest/actions/workflow-runs
SessionPhase mapRunStatus(String? status, String? conclusion) {
  switch (status) {
    case 'queued':
    case 'requested':
    case 'pending':
    case 'waiting':
      return SessionPhase.queued;
    case 'in_progress':
      return SessionPhase.running;
    case 'completed':
      return switch (conclusion) {
        'success' => SessionPhase.succeeded,
        'failure' || 'startup_failure' || 'action_required' => SessionPhase.failed,
        'cancelled' || 'stale' => SessionPhase.cancelled,
        'timed_out' => SessionPhase.timedOut,
        'skipped' || 'neutral' || null => SessionPhase.skipped,
        _ => SessionPhase.unknown,
      };
    default:
      return SessionPhase.unknown;
  }
}
