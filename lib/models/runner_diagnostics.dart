import 'dart:convert';
import '../core/utils/validators.dart';

/// Facts reported by the workflow itself through `WINPILOT|KEY=VALUE` lines.
/// Nothing here is assumed: a value is null until the runner printed it.
/// Verdict for the Tailscale link of a session. Only [verified] means "connected".
enum TailscaleStatus {
  notReported,
  verified,
  missingSecret,
  invalidSecret,
  joinFailed,
  rdpUnreachable,
  requiresRdp,
}

class RunnerDiagnostics {
  const RunnerDiagnostics({
    this.osName,
    this.osVersion,
    this.architecture,
    this.edition,
    this.runnerName,
    this.runnerImage,
    this.diagnosticsOk = false,
    this.rdpRequested,
    this.rdpUserReady,
    this.rdpReady,
    this.rdpReason,
    this.rdpPortListening,
    this.tailscaleState,
    this.tailscaleIp,
    this.tailscaleRdpProbe,
    this.tailscaleFailure,
    this.tailscaleError,
    this.stage,
    this.sessionEndsAt,
    this.sessionMinutes,
    this.lastHeartbeat,
    this.error,
  });

  static const empty = RunnerDiagnostics();

  final String? osName;
  final String? osVersion;
  final String? architecture;
  final String? edition;
  final String? runnerName;
  final String? runnerImage;
  final bool diagnosticsOk;
  final bool? rdpRequested;
  final bool? rdpUserReady;
  final bool? rdpReady;
  final String? rdpReason;
  final bool? rdpPortListening;
  final String? tailscaleState;
  final String? tailscaleIp;
  /// 'ok' only when the workflow reached TCP 3389 on the tailnet IP itself.
  final String? tailscaleRdpProbe;
  /// Category from the runner's own classification of `tailscale up` output
  /// (invalid_cli_flags, expired_key, revoked_or_used_key, invalid_key, daemon_not_running,
  /// network_or_control_plane, join_timeout, unknown). Never the key itself.
  final String? tailscaleFailure;
  /// First error line from `tailscale up`, with the auth key removed by the runner.
  final String? tailscaleError;
  final String? stage;
  final DateTime? sessionEndsAt;
  final int? sessionMinutes;
  final DateTime? lastHeartbeat;
  final String? error;

  /// Tailscale status as a verdict. "verified" needs BOTH a Tailscale IP in 100.64.0.0/10
  /// AND the workflow's own TCP 3389 probe on that address. Anything else is not claimed.
  TailscaleStatus get tailscaleStatus {
    final st = tailscaleState;
    if (st == null) return TailscaleStatus.notReported;
    switch (st) {
      case 'connected':
        final ip = tailscaleIp;
        if (ip == null || !Validators.isTailscaleIpv4(ip)) return TailscaleStatus.notReported;
        return tailscaleRdpProbe == 'ok' ? TailscaleStatus.verified : TailscaleStatus.rdpUnreachable;
      case 'missing_secret':
        return TailscaleStatus.missingSecret;
      case 'invalid_secret':
        return TailscaleStatus.invalidSecret;
      case 'join_failed':
      case 'no_tailscale_ip':
        return TailscaleStatus.joinFailed;
      case 'rdp_unreachable':
        return TailscaleStatus.rdpUnreachable;
      case 'requires_rdp':
        return TailscaleStatus.requiresRdp;
      default:
        return TailscaleStatus.notReported;
    }
  }

  bool get hasAnyData => osName != null || architecture != null || tailscaleState != null || rdpReady != null;
  bool get isX64 => const {'X64', 'AMD64'}.contains(architecture?.toUpperCase());
  bool get isWindows11 => osName?.contains('Windows 11') ?? false;

  static const _prefix = 'WINPILOT|';

  factory RunnerDiagnostics.parse(String logText) {
    final values = <String, String>{};
    for (final line in const LineSplitter().convert(logText)) {
      final index = line.indexOf(_prefix);
      if (index < 0) continue;
      final payload = line.substring(index + _prefix.length).trimRight();
      final eq = payload.indexOf('=');
      if (eq <= 0) continue;
      values[payload.substring(0, eq).trim()] = payload.substring(eq + 1).trim();
    }
    if (values.isEmpty) return empty;

    bool? flag(String key) {
      final v = values[key];
      if (v == null) return null;
      return v.toLowerCase() == 'true';
    }

    DateTime? time(String key) => DateTime.tryParse(values[key] ?? '')?.toLocal();

    return RunnerDiagnostics(
      osName: values['OS'],
      osVersion: values['OS_VERSION'],
      architecture: values['ARCH'],
      edition: values['EDITION'],
      runnerName: values['RUNNER'],
      runnerImage: values['RUNNER_IMAGE'],
      diagnosticsOk: values['DIAGNOSTICS'] == 'ok',
      rdpRequested: flag('RDP_REQUESTED') ?? (values.containsKey('RDP_CONFIGURED') ? true : null),
      rdpUserReady: flag('RDP_USER_READY'),
      rdpReady: flag('RDP_HANDSHAKE'),
      rdpReason: values['RDP_REASON'],
      rdpPortListening: flag('RDP_PORT_LISTENING'),
      tailscaleState: values['TS_STATE'],
      tailscaleIp: values['TS_IP'],
      tailscaleRdpProbe: values['TS_RDP_PROBE'],
      tailscaleFailure: values['TS_FAILURE'],
      tailscaleError: values['TS_ERROR'],
      stage: values['STAGE'],
      sessionEndsAt: time('SESSION_ENDS_AT'),
      sessionMinutes: int.tryParse(values['SESSION_MINUTES'] ?? ''),
      lastHeartbeat: time('HEARTBEAT'),
      error: values['ERROR'],
    );
  }

}
