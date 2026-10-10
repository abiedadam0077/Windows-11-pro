import '../core/config/app_config.dart';
import 'github_models.dart';
import 'runner_diagnostics.dart';
import 'session_phase.dart';

/// Parameters chosen in the setup wizard. Contains no secrets: the Windows
/// password and the Tailscale auth key live in GitHub Actions Secrets.
class SessionRequest {
  const SessionRequest({
    required this.workflowPath,
    required this.windowsUser,
    required this.enableRdp,
    required this.useTailscale,
    required this.sessionMinutes,
  });

  final String workflowPath;
  final String windowsUser;
  final bool enableRdp;
  final bool useTailscale;
  final int sessionMinutes;

  Map<String, Object> toInputs() => {
        'windows_username': windowsUser,
        'enable_rdp': enableRdp,
        'use_tailscale': useTailscale,
        'session_minutes': sessionMinutes.toString(),
      };

  Map<String, dynamic> toJson() => {
        'workflow_path': workflowPath,
        'windows_user': windowsUser,
        'enable_rdp': enableRdp,
        'use_tailscale': useTailscale,
        'session_minutes': sessionMinutes,
      };

  factory SessionRequest.fromJson(Map<String, dynamic> json) => SessionRequest(
        workflowPath: json['workflow_path'] as String? ?? AppConfig.defaultWorkflowPath,
        windowsUser: json['windows_user'] as String? ?? AppConfig.defaultWindowsUser,
        enableRdp: json['enable_rdp'] as bool? ?? false,
        useTailscale: json['use_tailscale'] as bool? ?? false,
        sessionMinutes: (json['session_minutes'] as num?)?.toInt() ?? AppConfig.defaultSessionMinutes,
      );
}

/// A locally remembered workflow run (persisted, no secrets).
class SessionRecord {
  const SessionRecord({
    required this.runId,
    required this.repoFullName,
    required this.branch,
    required this.request,
    required this.dispatchedAt,
    this.runNumber,
    this.htmlUrl,
    this.phase = SessionPhase.queued,
    this.runStartedAt,
    this.endedAt,
    this.displayTitle,
  });

  final int runId;
  final String repoFullName;
  final String branch;
  final SessionRequest request;
  final DateTime dispatchedAt;
  final int? runNumber;
  final String? htmlUrl;
  final SessionPhase phase;
  final DateTime? runStartedAt;
  final DateTime? endedAt;
  final String? displayTitle;

  String get owner => repoFullName.split('/').first;
  String get repoName => repoFullName.split('/').skip(1).join('/');

  /// Start time used for elapsed/remaining calculations.
  DateTime get startedAt => runStartedAt ?? dispatchedAt;

  SessionRecord copyWith({
    SessionPhase? phase,
    DateTime? runStartedAt,
    DateTime? endedAt,
    int? runNumber,
    String? htmlUrl,
    String? displayTitle,
  }) =>
      SessionRecord(
        runId: runId,
        repoFullName: repoFullName,
        branch: branch,
        request: request,
        dispatchedAt: dispatchedAt,
        runNumber: runNumber ?? this.runNumber,
        htmlUrl: htmlUrl ?? this.htmlUrl,
        phase: phase ?? this.phase,
        runStartedAt: runStartedAt ?? this.runStartedAt,
        endedAt: endedAt ?? this.endedAt,
        displayTitle: displayTitle ?? this.displayTitle,
      );

  Map<String, dynamic> toJson() => {
        'run_id': runId,
        'repo': repoFullName,
        'branch': branch,
        'request': request.toJson(),
        'dispatched_at': dispatchedAt.toUtc().toIso8601String(),
        'run_number': runNumber,
        'html_url': htmlUrl,
        'phase': phase.name,
        'run_started_at': runStartedAt?.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'display_title': displayTitle,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        runId: (json['run_id'] as num).toInt(),
        repoFullName: json['repo'] as String? ?? '',
        branch: json['branch'] as String? ?? 'main',
        request: SessionRequest.fromJson(asJsonMap(json['request'])),
        dispatchedAt: DateTime.parse(json['dispatched_at'] as String).toLocal(),
        runNumber: (json['run_number'] as num?)?.toInt(),
        htmlUrl: json['html_url'] as String?,
        phase: SessionPhase.values.firstWhere(
          (p) => p.name == json['phase'],
          orElse: () => SessionPhase.unknown,
        ),
        runStartedAt: _parseLocal(json['run_started_at']),
        endedAt: _parseLocal(json['ended_at']),
        displayTitle: json['display_title'] as String?,
      );

  static DateTime? _parseLocal(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// Live data for the active run, fetched from GitHub.
class SessionSnapshot {
  const SessionSnapshot({
    required this.run,
    required this.jobs,
    required this.diagnostics,
    required this.artifacts,
    required this.logsAvailable,
    required this.fetchedAt,
  });

  final WorkflowRun run;
  final List<WorkflowJob> jobs;
  final RunnerDiagnostics diagnostics;
  final List<ArtifactInfo> artifacts;
  final bool logsAvailable;
  final DateTime fetchedAt;

  WorkflowJob? get primaryJob {
    if (jobs.isEmpty) return null;
    for (final job in jobs) {
      if (job.labels.contains(AppConfig.runnerLabel)) return job;
    }
    return jobs.first;
  }
}

enum ActivityKind { info, success, warning, error }

class ActivityEntry {
  const ActivityEntry({
    required this.at,
    required this.key,
    this.args = const {},
    this.kind = ActivityKind.info,
  });

  final DateTime at;
  final String key;
  final Map<String, String> args;
  final ActivityKind kind;
}

/// Readiness of a repository for starting a session (checked against GitHub).
class RepoReadiness {
  const RepoReadiness({
    required this.fullName,
    required this.isPrivate,
    this.actionsEnabled,
    this.workflowFile,
    this.passwordSecret,
    this.tailscaleSecret,
    this.blockers = const [],
    this.warnings = const [],
  });

  final String fullName;
  final bool isPrivate;

  /// null means "could not verify" (for example missing admin permission).
  final bool? actionsEnabled;
  final RepoFile? workflowFile;
  final bool? passwordSecret;
  final bool? tailscaleSecret;

  /// Localization keys of problems that block starting a session.
  final List<String> blockers;

  /// Localization keys of non-blocking notes.
  final List<String> warnings;

  bool get workflowExists => workflowFile != null;
  /// True only when the installed workflow is the current template (not an older copy).
  bool get workflowCurrent =>
      workflowFile != null && workflowFile!.content.contains(AppConfig.workflowRevisionMarker);
  bool get canStart => blockers.isEmpty;
}
