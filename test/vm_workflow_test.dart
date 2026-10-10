import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Static checks on the VM workflow template the app installs. These run in CI.
// They do not start a VM; a real run is a separate, approved test.
void main() {
  final text = File('assets/workflows/verify-windows-11.yml').readAsStringSync();

  group('VM workflow template (static, unit level)', () {
    test('the installed copy is identical to the asset', () {
      final copy = File('.github/workflows/verify-windows-11.yml').readAsStringSync();
      expect(copy, text);
    });

    test('reads all three secrets through env, never on the command line', () {
      for (final name in ['WINPILOT_WIN_PASSWORD', 'BACKUP_PASSWORD', 'ACCESS_PASSWORD']) {
        expect(text, contains('secrets.$name'));
      }
      expect(text, contains('--env-file'));
      expect(RegExp(r'docker run[^\n]*PASSWORD=').hasMatch(text), isFalse);
    });

    test('web viewer is loopback only; RDP is published', () {
      expect(text, contains('-p 127.0.0.1:8006:8006'));
      expect(text, contains('-p 3389:3389/tcp'));
      expect(RegExp(r'-p 8006:8006').hasMatch(text), isFalse);
    });

    test('the access URL is never printed', () {
      final printing = RegExp(r'echo[^\n]*\$url|echo[^\n]*\$\{url\}');
      expect(printing.hasMatch(text), isFalse);
    });

    test('backup keeps the previous backups until the new one is verified', () {
      final verifyAt = text.indexOf("echo \"WINPILOT|BACKUP=verified\"");
      final pruneAt = text.indexOf('.[2:]');
      expect(verifyAt, greaterThan(0));
      expect(pruneAt, greaterThan(verifyAt));
    });

    test('restore never deletes existing backups and stops on low storage', () {
      expect(text, contains('RESTORE_STATE=low_storage'));
      expect(text, contains('failed_low_storage'));
      final restoreStart = text.indexOf('WinPilot: restore the latest valid backup');
      final restoreEnd = text.indexOf('WinPilot: start Windows 11 Pro VM');
      expect(restoreStart, greaterThan(0));
      expect(restoreEnd, greaterThan(restoreStart));
      expect(text.substring(restoreStart, restoreEnd), isNot(contains('release delete')));
    });

    test('Tailscale is opt-in by default', () {
      expect(text, contains("default: false\n        type: boolean\n      session_minutes"));
    });
  });
}
