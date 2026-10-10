import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/utils/validators.dart';

void main() {
  group('Tailscale IPv4 validation', () {
    test('accepts addresses inside 100.64.0.0/10', () {
      expect(Validators.isTailscaleIpv4('100.64.0.1'), isTrue);
      expect(Validators.isTailscaleIpv4('100.101.102.103'), isTrue);
      expect(Validators.isTailscaleIpv4('100.127.255.254'), isTrue);
    });

    test('rejects addresses outside the CGNAT range', () {
      expect(Validators.isTailscaleIpv4('100.128.0.1'), isFalse);
      expect(Validators.isTailscaleIpv4('100.63.255.255'), isFalse);
      expect(Validators.isTailscaleIpv4('192.168.1.10'), isFalse);
      expect(Validators.isTailscaleIpv4('10.0.0.1'), isFalse);
    });

    test('rejects malformed input', () {
      expect(Validators.isTailscaleIpv4(''), isFalse);
      expect(Validators.isTailscaleIpv4('100.64.0'), isFalse);
      expect(Validators.isTailscaleIpv4('100.64.0.999'), isFalse);
      expect(Validators.isTailscaleIpv4('not-an-ip'), isFalse);
    });
  });

  group('Windows username', () {
    test('accepts a plain local account name', () {
      expect(Validators.isValidWindowsUsername('winpilot'), isTrue);
    });

    test('rejects too-short and invalid names', () {
      expect(Validators.isValidWindowsUsername('ab'), isFalse);
      expect(Validators.isValidWindowsUsername('1startsWithDigit'), isFalse);
      expect(Validators.isValidWindowsUsername('has space'), isFalse);
    });
  });

  group('Workflow path', () {
    test('requires a file under .github/workflows', () {
      expect(Validators.isValidWorkflowPath('.github/workflows/verify-windows-11.yml'), isTrue);
      expect(Validators.isValidWorkflowPath('.github/workflows/../x.yml'), isFalse);
      expect(Validators.isValidWorkflowPath('scripts/run.yml'), isFalse);
    });
  });

  group('Password policy', () {
    test('reports every unmet rule for a weak password', () {
      final v = PasswordPolicy.violations('short');
      expect(v, containsAll(['pw_rule_length', 'pw_rule_upper', 'pw_rule_digit', 'pw_rule_symbol']));
    });

    test('accepts a strong password that does not contain the username', () {
      expect(PasswordPolicy.violations('Strong-Passw0rd!', username: 'winpilot'), isEmpty);
    });

    test('flags a password containing the username', () {
      expect(
        PasswordPolicy.violations('WinPilot-Passw0rd!', username: 'winpilot'),
        contains('pw_rule_username'),
      );
    });

    test('generated passwords satisfy the policy', () {
      for (var i = 0; i < 20; i++) {
        final pw = PasswordPolicy.generate();
        expect(pw.length, greaterThanOrEqualTo(PasswordPolicy.minLength));
        expect(PasswordPolicy.violations(pw), isEmpty);
      }
    });
  });
}
