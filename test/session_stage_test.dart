import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/models/runner_diagnostics.dart';
import 'package:winpilot/models/session_phase.dart';
import 'package:winpilot/models/session_stage.dart';

RunnerDiagnostics _diag({String? stage, bool? rdpReady}) => RunnerDiagnostics(
      diagnosticsOk: true,
      stage: stage,
      rdpReady: rdpReady,
    );

void main() {
  group('Session stage (unit)', () {
    test('queued and terminal GitHub states map directly', () {
      expect(deriveSessionStage(SessionPhase.queued, null), SessionStage.queued);
      expect(deriveSessionStage(SessionPhase.succeeded, null), SessionStage.completed);
      expect(deriveSessionStage(SessionPhase.failed, _diag(stage: 'session', rdpReady: true)),
          SessionStage.failed);
      expect(deriveSessionStage(SessionPhase.cancelled, null), SessionStage.failed);
      expect(deriveSessionStage(SessionPhase.timedOut, null), SessionStage.failed);
    });

    test('running without runner markers is Starting, never Running', () {
      expect(deriveSessionStage(SessionPhase.running, null), SessionStage.starting);
      expect(deriveSessionStage(SessionPhase.running, _diag(stage: 'vm_start')), SessionStage.starting);
    });

    test('Windows is Waiting while the VM boots, until the RDP handshake is seen', () {
      expect(deriveSessionStage(SessionPhase.running, _diag(stage: 'windows_boot')),
          SessionStage.waitingForWindows);
      expect(deriveSessionStage(SessionPhase.running, _diag(stage: 'windows_boot', rdpReady: false)),
          SessionStage.waitingForWindows);
    });

    test('Running needs the verified RDP handshake', () {
      expect(deriveSessionStage(SessionPhase.running, _diag(stage: 'session', rdpReady: true)),
          SessionStage.running);
      // Declared but not verified: must not count as Running.
      expect(deriveSessionStage(SessionPhase.running, _diag(stage: 'session')), SessionStage.starting);
    });

    test('shutdown and backup stages are Saving backup', () {
      for (final stage in ['shutdown', 'backup', 'done']) {
        expect(deriveSessionStage(SessionPhase.running, _diag(stage: stage, rdpReady: true)),
            SessionStage.savingBackup);
      }
    });
  });
}
