import 'session_phase.dart';

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

Map<String, dynamic> asJsonMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> asJsonList(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

class GitHubUser {
  const GitHubUser({required this.login, this.name, this.avatarUrl, this.htmlUrl});

  final String login;
  final String? name;
  final String? avatarUrl;
  final String? htmlUrl;

  factory GitHubUser.fromJson(Map<String, dynamic> json) => GitHubUser(
        login: json['login'] as String? ?? '',
        name: json['name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        htmlUrl: json['html_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'login': login,
        'name': name,
        'avatar_url': avatarUrl,
        'html_url': htmlUrl,
      };
}

class RepoSummary {
  const RepoSummary({
    required this.id,
    required this.owner,
    required this.name,
    required this.isPrivate,
    required this.defaultBranch,
    required this.htmlUrl,
    this.description,
    this.canPush = false,
    this.canAdmin = false,
    this.updatedAt,
  });

  final int id;
  final String owner;
  final String name;
  final bool isPrivate;
  final String defaultBranch;
  final String htmlUrl;
  final String? description;
  final bool canPush;
  final bool canAdmin;
  final DateTime? updatedAt;

  String get fullName => '$owner/$name';

  factory RepoSummary.fromJson(Map<String, dynamic> json) {
    final owner = asJsonMap(json['owner'])['login'] as String? ?? '';
    final perms = asJsonMap(json['permissions']);
    return RepoSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      owner: owner,
      name: json['name'] as String? ?? '',
      isPrivate: json['private'] as bool? ?? false,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      htmlUrl: json['html_url'] as String? ?? '',
      description: json['description'] as String?,
      canPush: perms['push'] as bool? ?? false,
      canAdmin: perms['admin'] as bool? ?? false,
      updatedAt: _date(json['updated_at']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RepoSummary && other.fullName == fullName && other.canPush == canPush;

  @override
  int get hashCode => Object.hash(fullName, canPush);
}

class RepoFile {
  const RepoFile({required this.path, required this.sha, required this.content, this.htmlUrl});

  final String path;
  final String sha;
  final String content;
  final String? htmlUrl;
}

class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.runNumber,
    required this.status,
    required this.htmlUrl,
    this.name = '',
    this.displayTitle = '',
    this.conclusion,
    this.createdAt,
    this.runStartedAt,
    this.updatedAt,
    this.headBranch,
    this.event,
  });

  final int id;
  final int runNumber;
  final String status;
  final String? conclusion;
  final String name;
  final String displayTitle;
  final DateTime? createdAt;
  final DateTime? runStartedAt;
  final DateTime? updatedAt;
  final String htmlUrl;
  final String? headBranch;
  final String? event;

  SessionPhase get phase => mapRunStatus(status, conclusion);

  factory WorkflowRun.fromJson(Map<String, dynamic> json) => WorkflowRun(
        id: (json['id'] as num?)?.toInt() ?? 0,
        runNumber: (json['run_number'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'unknown',
        conclusion: json['conclusion'] as String?,
        name: json['name'] as String? ?? '',
        displayTitle: json['display_title'] as String? ?? '',
        createdAt: _date(json['created_at']),
        runStartedAt: _date(json['run_started_at']),
        updatedAt: _date(json['updated_at']),
        htmlUrl: json['html_url'] as String? ?? '',
        headBranch: json['head_branch'] as String?,
        event: json['event'] as String?,
      );
}

class WorkflowStep {
  const WorkflowStep({required this.number, required this.name, required this.status, this.conclusion});

  final int number;
  final String name;
  final String status;
  final String? conclusion;

  factory WorkflowStep.fromJson(Map<String, dynamic> json) => WorkflowStep(
        number: (json['number'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? 'queued',
        conclusion: json['conclusion'] as String?,
      );
}

class WorkflowJob {
  const WorkflowJob({
    required this.id,
    required this.name,
    required this.status,
    required this.labels,
    required this.steps,
    this.conclusion,
    this.startedAt,
    this.completedAt,
    this.runnerName,
    this.htmlUrl,
  });

  final int id;
  final String name;
  final String status;
  final String? conclusion;
  final List<String> labels;
  final List<WorkflowStep> steps;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? runnerName;
  final String? htmlUrl;

  SessionPhase get phase => mapRunStatus(status, conclusion);

  factory WorkflowJob.fromJson(Map<String, dynamic> json) => WorkflowJob(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? 'queued',
        conclusion: json['conclusion'] as String?,
        labels: (json['labels'] as List?)?.whereType<String>().toList() ?? const [],
        steps: asJsonList(json['steps']).map(WorkflowStep.fromJson).toList(),
        startedAt: _date(json['started_at']),
        completedAt: _date(json['completed_at']),
        runnerName: json['runner_name'] as String?,
        htmlUrl: json['html_url'] as String?,
      );
}

class ArtifactInfo {
  const ArtifactInfo({
    required this.id,
    required this.name,
    required this.sizeInBytes,
    required this.expired,
    this.createdAt,
    this.expiresAt,
  });

  final int id;
  final String name;
  final int sizeInBytes;
  final bool expired;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  factory ArtifactInfo.fromJson(Map<String, dynamic> json) => ArtifactInfo(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'artifact',
        sizeInBytes: (json['size_in_bytes'] as num?)?.toInt() ?? 0,
        expired: json['expired'] as bool? ?? false,
        createdAt: _date(json['created_at']),
        expiresAt: _date(json['expires_at']),
      );
}
