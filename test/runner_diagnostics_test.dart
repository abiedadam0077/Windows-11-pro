import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/models/runner_diagnostics.dart';

void main() {
  test('parses WINPILOT markers from log text', () {
    const log = '''
2026-10-10T10:00:00Z some unrelated line
2026-10-10T10:00:01Z WINPILOT|OS=Microsoft Windows 11 Pro
2026-10-10T10:00:01Z WINPILOT|ARCH=x64
2026-10-10T10:00:02Z WINPILOT|RDP_READY=true
2026-10-10T10:00:02Z WINPILOT|TS_IP=100.100.10.20
2026-10-10T10:00:03Z WINPILOT|SESSION_ENDS_AT=2026-10-10T12:00:00Z
''';
    final d = RunnerDiagnostics.parse(log);
    expect(d.osName, 'Microsoft Windows 11 Pro');
    expect(d.isX64, isTrue);
    expect(d.isWindows11, isTrue);
    expect(d.rdpReady, isTrue);
    expect(d.tailscaleIp, '100.100.10.20');
    expect(d.sessionEndsAt, isNotNull);
    expect(d.hasAnyData, isTrue);
  });

  test('does not invent Tailscale state when the runner did not report it', () {
    final d = RunnerDiagnostics.parse('WINPILOT|TS_IP=100.64.1.2');
    expect(d.tailscaleIp, '100.64.1.2');
    expect(d.tailscaleState, isNull);
  });

  test('RDP readiness stays unknown when not declared', () {
    final d = RunnerDiagnostics.parse('WINPILOT|OS=Windows 11');
    expect(d.rdpReady, isNull);
  });

  test('empty log yields no data', () {
    expect(RunnerDiagnostics.parse('').hasAnyData, isFalse);
  });
}
