import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/models/runner_diagnostics.dart';

// Tests for the Tailscale join step. The flags are checked against the flags that
// `tailscale up` really defines (cmd/tailscale/cli/up.go, v1.104.1). The classifier is the
// exact Python script embedded in the workflow, run on sample outputs.
const _upFlags = {'auth-key', 'hostname', 'accept-dns', 'timeout'};
const _key = 'tskey-auth-kTESTabcdef123456-CNTRLxyz9876';

String _wf() => File('assets/workflows/verify-windows-11.yml').readAsStringSync();

String _upCommand(String text) {
  final start = text.indexOf('sudo tailscale up');
  expect(start, greaterThan(-1), reason: 'the join step must call tailscale up');
  final end = text.indexOf('>"\$SCRATCH/ts-up.log"', start);
  expect(end, greaterThan(start));
  return text.substring(start, end);
}

String _classifierScript(String text) {
  const marker = "cat > \"\$SCRATCH/ts_classify.py\" <<'PY'\n";
  final a = text.indexOf(marker);
  expect(a, greaterThan(-1), reason: 'classifier must be written by the workflow');
  final b = text.indexOf('\n          PY\n', a + marker.length);
  expect(b, greaterThan(a));
  // Remove the 10-space YAML indentation of the run block.
  return text
      .substring(a + marker.length, b)
      .split('\n')
      .map((l) => l.startsWith('          ') ? l.substring(10) : l)
      .join('\n');
}

Future<Map<String, String>> _classify(String logText) async {
  final dir = await Directory.systemTemp.createTemp('ts-classify-');
  addTearDown(() => dir.delete(recursive: true));
  final script = File('${dir.path}/ts_classify.py')..writeAsStringSync(_classifierScript(_wf()));
  final log = File('${dir.path}/ts-up.log')..writeAsStringSync(logText);
  final r = await Process.run('python3', [script.path, log.path],
      environment: {'TS_AUTHKEY': _key});
  expect(r.exitCode, 0, reason: r.stderr.toString());
  final out = <String, String>{};
  for (final line in (r.stdout as String).split('\n')) {
    final i = line.indexOf('=');
    if (line.startsWith('WINPILOT|') && i > 0) {
      out[line.substring('WINPILOT|'.length, i)] = line.substring(i + 1);
    }
  }
  return out;
}

void main() {
  group('tailscale up command (static, checked against upstream flags)', () {
    test('uses only flags that tailscale up defines', () {
      final flags = RegExp(r'--([a-z-]+)')
          .allMatches(_upCommand(_wf()))
          .map((m) => m.group(1)!)
          .toSet();
      expect(flags, isNotEmpty);
      expect(_upFlags.containsAll(flags), isTrue, reason: 'unknown flags: ${flags.difference(_upFlags)}');
    });

    test('does not pass --ephemeral (a property of the auth key, not a flag) or --authkey', () {
      final cmd = _upCommand(_wf());
      expect(cmd, isNot(contains('--ephemeral')));
      expect(cmd, isNot(contains('--authkey')));
    });

    test('passes the key from a 0600 file, never on the command line', () {
      final cmd = _upCommand(_wf());
      expect(cmd, contains('--auth-key="file:\$keyfile"'));
      expect(_wf(), contains("printf '%s' \"\$TS_AUTHKEY\" > \"\$keyfile\""));
      expect(_wf(), contains('rm -f "\$keyfile"'));
    });

    test('the key is never echoed or put in the mask command', () {
      expect(_wf(), isNot(contains('add-mask::\$TS_AUTHKEY')));
      expect(RegExp(r'echo[^\n]*\$TS_AUTHKEY').hasMatch(_wf()), isFalse);
    });
  });

  group('join failure classifier (the workflow script, run on sample output)', () {
    test('invalid CLI flag is a workflow bug, not a key problem', () async {
      final o = await _classify('flag provided but not defined: -ephemeral\nusage: tailscale up [flags]\n');
      expect(o['TS_FAILURE'], 'invalid_cli_flags');
      expect(o['TS_ERROR'], 'flag provided but not defined: -ephemeral');
    });

    test('expired and revoked/used keys are distinct', () async {
      expect((await _classify('backend error: auth key has expired'))['TS_FAILURE'], 'expired_key');
      expect((await _classify('auth key revoked'))['TS_FAILURE'], 'revoked_or_used_key');
    });

    test('network and timeout failures are not reported as key failures', () async {
      expect(
          (await _classify('dial tcp: lookup controlplane.tailscale.com: no such host'))['TS_FAILURE'],
          'network_or_control_plane');
      expect((await _classify('timed out waiting for tailscaled to enter Running'))['TS_FAILURE'], 'join_timeout');
    });

    test('an error the classifier does not know is unknown and still shown', () async {
      final o = await _classify('something new went wrong');
      expect(o['TS_FAILURE'], 'unknown');
      expect(o['TS_ERROR'], contains('something new went wrong'));
    });

    test('the auth key never appears in the printed error', () async {
      final o = await _classify('invalid key $_key was rejected\nerror: $_key');
      expect(o.values.join(' '), isNot(contains(_key)));
      expect(o['TS_ERROR'], contains('tskey-***'));
    });
  });

  group('join failure in the app (unit)', () {
    test('a join failure carries the category and the redacted original error', () {
      final d = RunnerDiagnostics.parse(
          'WINPILOT|TS_STATE=join_failed\nWINPILOT|TS_FAILURE=invalid_cli_flags\nWINPILOT|TS_ERROR=flag provided but not defined: -ephemeral');
      expect(d.tailscaleStatus, TailscaleStatus.joinFailed);
      expect(d.tailscaleFailure, 'invalid_cli_flags');
      expect(d.tailscaleError, 'flag provided but not defined: -ephemeral');
    });

    test('an old log without TS_FAILURE does not invent a category', () {
      final d = RunnerDiagnostics.parse('WINPILOT|TS_STATE=join_failed');
      expect(d.tailscaleStatus, TailscaleStatus.joinFailed);
      expect(d.tailscaleFailure, isNull);
    });
  });
}
