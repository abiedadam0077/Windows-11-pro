import 'runner_diagnostics.dart';
import 'session_phase.dart';

/// What the user sees for a session. Derived only from GitHub run state and the runner's own
/// markers. Windows counts as Running only after the runner proved an RDP handshake on 3389.
enum SessionStage { queued, starting, waitingForWindows, running, savingBackup, completed, failed }

SessionStage deriveSessionStage(SessionPhase phase, RunnerDiagnostics? diag) {
  switch (phase) {
    case SessionPhase.queued:
      return SessionStage.queued;
    case SessionPhase.succeeded:
      return SessionStage.completed;
    case SessionPhase.failed:
    case SessionPhase.cancelled:
    case SessionPhase.timedOut:
    case SessionPhase.skipped:
      return SessionStage.failed;
    case SessionPhase.running:
    case SessionPhase.unknown:
      break;
  }
  final stage = diag?.stage;
  if (stage == 'shutdown' || stage == 'backup' || stage == 'done') return SessionStage.savingBackup;
  // Only a verified RDP handshake (runner marker RDP_HANDSHAKE=true) means Windows is up.
  if (diag?.rdpReady == true) return SessionStage.running;
  if (stage == 'windows_boot') return SessionStage.waitingForWindows;
  return SessionStage.starting;
}

extension SessionStageX on SessionStage {
  String get labelKey => switch (this) {
        SessionStage.queued => 'stage_queued',
        SessionStage.starting => 'stage_starting',
        SessionStage.waitingForWindows => 'stage_waiting_windows',
        SessionStage.running => 'stage_running',
        SessionStage.savingBackup => 'stage_saving_backup',
        SessionStage.completed => 'stage_completed',
        SessionStage.failed => 'stage_failed',
      };
}
