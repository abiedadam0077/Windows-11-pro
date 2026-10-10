import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/models/session_phase.dart';

void main() {
  test('maps GitHub run status and conclusion to phases', () {
    expect(mapRunStatus('queued', null), SessionPhase.queued);
    expect(mapRunStatus('in_progress', null), SessionPhase.running);
    expect(mapRunStatus('completed', 'success'), SessionPhase.succeeded);
    expect(mapRunStatus('completed', 'failure'), SessionPhase.failed);
    expect(mapRunStatus('completed', 'cancelled'), SessionPhase.cancelled);
    expect(mapRunStatus('completed', 'timed_out'), SessionPhase.timedOut);
  });

  test('active and terminal flags are consistent', () {
    expect(SessionPhase.running.isActive, isTrue);
    expect(SessionPhase.running.isTerminal, isFalse);
    expect(SessionPhase.succeeded.isTerminal, isTrue);
    expect(SessionPhase.succeeded.isActive, isFalse);
  });
}
