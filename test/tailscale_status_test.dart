import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/utils/validators.dart';
import 'package:winpilot/models/runner_diagnostics.dart';

void main() {
  TailscaleStatus verdict(String log) => RunnerDiagnostics.parse(log).tailscaleStatus;

  group('Tailscale verdict (unit)', () {
    test('connected needs IP in 100.64.0.0/10 AND the tailnet RDP probe', () {
      expect(
        verdict('WINPILOT|TS_STATE=connected\nWINPILOT|TS_IP=100.101.2.3\nWINPILOT|TS_RDP_PROBE=ok'),
        TailscaleStatus.verified,
      );
    });

    test('connected without the probe is NOT verified', () {
      expect(
        verdict('WINPILOT|TS_STATE=connected\nWINPILOT|TS_IP=100.101.2.3'),
        isNot(TailscaleStatus.verified),
      );
    });

    test('an IP outside the Tailscale range is never shown as connected', () {
      expect(
        verdict('WINPILOT|TS_STATE=connected\nWINPILOT|TS_IP=10.0.0.5\nWINPILOT|TS_RDP_PROBE=ok'),
        isNot(TailscaleStatus.verified),
      );
    });

    test('failure markers map to specific reasons', () {
      expect(verdict('WINPILOT|TS_STATE=missing_secret'), TailscaleStatus.missingSecret);
      expect(verdict('WINPILOT|TS_STATE=invalid_secret'), TailscaleStatus.invalidSecret);
      expect(verdict('WINPILOT|TS_STATE=join_failed'), TailscaleStatus.joinFailed);
      expect(verdict('WINPILOT|TS_STATE=rdp_unreachable'), TailscaleStatus.rdpUnreachable);
      expect(verdict('WINPILOT|TS_STATE=requires_rdp'), TailscaleStatus.requiresRdp);
    });

    test('no marker means not reported, never connected', () {
      expect(verdict('WINPILOT|STAGE=session'), TailscaleStatus.notReported);
    });
  });

  group('Tailscale auth key format (unit)', () {
    test('accepts tskey- keys and rejects others', () {
      expect(Validators.isValidTailscaleAuthKey('tskey-auth-kAbC123-XyZ987abc'), isTrue);
      expect(Validators.isValidTailscaleAuthKey('  tskey-auth-kAbC123-XyZ987abc  '), isTrue);
      expect(Validators.isValidTailscaleAuthKey('tskey-'), isFalse);
      expect(Validators.isValidTailscaleAuthKey('ghp_notatskey'), isFalse);
      expect(Validators.isValidTailscaleAuthKey('tskey-auth with space'), isFalse);
    });
  });
}
