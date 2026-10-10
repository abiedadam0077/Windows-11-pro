import 'dart:convert';

/// Facts reported by the workflow itself through `WINPILOT|KEY=VALUE` lines.
/// Nothing here is assumed: a value is null until the runner printed it.
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
  final String? stage;
  final DateTime? sessionEndsAt;
  final int? sessionMinutes;
  final DateTime? lastHeartbeat;
  final String? error;

  bool get hasAnyData => osName != null || architecture != null || tailscaleState != null || rdpReady != null;
  bool get isArm64 => architecture?.toUpperCase() == 'ARM64';
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
      rdpReady: flag('RDP_READY'),
      rdpReason: values['RDP_REASON'],
      rdpPortListening: flag('RDP_PORT_LISTENING'),
      tailscaleState: values['TS_STATE'],
      tailscaleIp: values['TS_IP'],
      stage: values['STAGE'],
      sessionEndsAt: time('SESSION_ENDS_AT'),
      sessionMinutes: int.tryParse(values['SESSION_MINUTES'] ?? ''),
      lastHeartbeat: time('HEARTBEAT'),
      error: values['ERROR'],
    );
  }

}
