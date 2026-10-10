import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/security/redactor.dart';
import '../../models/github_models.dart';
import '../../models/runner_diagnostics.dart';
import '../../models/session_models.dart';
import '../../models/session_phase.dart';
import '../services/github_api.dart';

/// Business operations built on [GitHubApi]: readiness checks, workflow
/// installation (with conflict handling), dispatching runs and polling state.
class GitHubRepository {
  GitHubRepository(this._api);

  final GitHubApi _api;

  Future<List<RepoSummary>> repositories() => _api.listRepositories();

  Future<RepoSummary> createRepository({
    required String name,
    required bool isPrivate,
    String? description,
  }) =>
      _api.createRepository(name: name, isPrivate: isPrivate, description: description);

  /// Checks everything that can be verified before starting a session.
  Future<RepoReadiness> checkReadiness(RepoSummary repo, String workflowPath) async {
    final blockers = <String>[];
    final warnings = <String>[];

    if (!repo.canPush) blockers.add('blocker_no_push');

    final enabled = await _api.actionsEnabled(repo.owner, repo.name);
    if (enabled == false) blockers.add('blocker_actions_disabled');
    if (enabled == null) warnings.add('warn_actions_unknown');

    if (repo.isPrivate) warnings.add('warn_private_repo_arm');

    final file = await _api.getFile(repo.owner, repo.name, workflowPath, ref: repo.defaultBranch);
    if (file == null) warnings.add('warn_workflow_missing');

    final password = await _api.secretExists(repo.owner, repo.name, AppConfig.windowsPasswordSecret);
    final tailscale = await _api.secretExists(repo.owner, repo.name, AppConfig.tailscaleAuthKeySecret);
    if (password == null) warnings.add('warn_secret_unknown');

    return RepoReadiness(
      fullName: repo.fullName,
      isPrivate: repo.isPrivate,
      actionsEnabled: enabled,
      workflowFile: file,
      passwordSecret: password,
      tailscaleSecret: tailscale,
      blockers: blockers,
      warnings: warnings,
    );
  }

  Future<RepoSecretsStatus> secretsStatus(RepoSummary repo) async => RepoSecretsStatus(
        password: await _api.secretExists(repo.owner, repo.name, AppConfig.windowsPasswordSecret),
        tailscale: await _api.secretExists(repo.owner, repo.name, AppConfig.tailscaleAuthKeySecret),
      );

  /// Writes the workflow file. Callers must have confirmed overwrites.
  Future<void> installWorkflow({
    required RepoSummary repo,
    required String path,
    required String content,
    String? existingSha,
  }) =>
      _api.putFile(
        owner: repo.owner,
        repo: repo.name,
        path: path,
        content: content,
        message: 'Add WinPilot Windows 11 Pro x64 (Docker + KVM) workflow',
        branch: repo.defaultBranch,
        sha: existingSha,
      );

  /// Dispatches the workflow and finds the run it created.
  Future<SessionRecord> dispatchAndFindRun({
    required String owner,
    required String repo,
    required String branch,
    required SessionRequest request,
  }) async {
    final dispatchedAt = DateTime.now();
    await _api.dispatchWorkflow(
      owner: owner,
      repo: repo,
      workflowPath: request.workflowPath,
      ref: branch,
      inputs: request.toInputs(),
    );

    WorkflowRun? found;
    for (var attempt = 0; attempt < 8 && found == null; attempt++) {
      await Future<void>.delayed(Duration(seconds: attempt == 0 ? 2 : 3));
      final runs = await _api.listRuns(
        owner: owner,
        repo: repo,
        workflowPath: request.workflowPath,
        event: 'workflow_dispatch',
        perPage: 10,
      );
      final threshold = dispatchedAt.subtract(const Duration(seconds: 20));
      for (final run in runs) {
        final created = run.createdAt;
        if (created != null && !created.isBefore(threshold)) {
          found = run;
          break; // GitHub returns newest first.
        }
      }
    }
    if (found == null) {
      throw const AppFailure(FailureKind.runNotFound);
    }
    return SessionRecord(
      runId: found.id,
      repoFullName: '$owner/$repo',
      branch: branch,
      request: request,
      dispatchedAt: dispatchedAt,
      runNumber: found.runNumber,
      htmlUrl: found.htmlUrl,
      phase: found.phase,
      displayTitle: found.displayTitle,
      runStartedAt: found.runStartedAt,
    );
  }

  Future<SessionSnapshot> snapshot({
    required String owner,
    required String repo,
    required int runId,
  }) async {
    final run = await _api.getRun(owner, repo, runId);
    final jobs = await _api.listJobs(owner, repo, runId);

    var diagnostics = RunnerDiagnostics.empty;
    var logsAvailable = false;
    final job = _pickJob(jobs);
    if (job != null && job.phase != SessionPhase.queued) {
      try {
        final text = await _api.jobLogs(owner, repo, job.id);
        if (text.isNotEmpty) {
          diagnostics = RunnerDiagnostics.parse(text);
          logsAvailable = true;
        }
      } on AppFailure catch (e) {
        // Logs can be unavailable while a job starts or after retention ends.
        if (e.kind != FailureKind.notFound) rethrow;
      }
    }

    // Artifacts are optional for the status card: a failure here must not hide the run status.
    var artifacts = const <ArtifactInfo>[];
    if (run.phase.isTerminal) {
      try {
        artifacts = await _api.listArtifacts(owner, repo, runId);
      } on AppFailure catch (e) {
        if (e.kind == FailureKind.unauthorized || e.kind == FailureKind.forbidden) rethrow;
      }
    }

    return SessionSnapshot(
      run: run,
      jobs: jobs,
      diagnostics: diagnostics,
      artifacts: artifacts,
      logsAvailable: logsAvailable,
      fetchedAt: DateTime.now(),
    );
  }

  /// Returns the last [AppConfig.maxLogLines] redacted lines of the main job.
  Future<List<String>> logLines({
    required String owner,
    required String repo,
    required int runId,
  }) async {
    final jobs = await _api.listJobs(owner, repo, runId);
    final job = _pickJob(jobs);
    if (job == null) return const [];
    final String text;
    try {
      text = await _api.jobLogs(owner, repo, job.id);
    } on AppFailure catch (e) {
      // Not published yet or expired: an empty list shows the "no logs yet" state, not a network error.
      if (e.kind == FailureKind.notFound) return const [];
      rethrow;
    }
    final lines = SecretRedactor.redact(text).split('\n');
    if (lines.length <= AppConfig.maxLogLines) return lines;
    return lines.sublist(lines.length - AppConfig.maxLogLines);
  }

  Future<List<WorkflowRun>> historyRuns({
    required String owner,
    required String repo,
    required String workflowPath,
  }) =>
      _api.listRuns(
        owner: owner,
        repo: repo,
        workflowPath: workflowPath,
        perPage: 50,
      );

  /// Asks the running session to shut Windows down and save its backup.
  /// Unlike cancel, the workflow keeps running long enough to do that.
  Future<void> requestStop({required String owner, required String repo, required int runId}) =>
      _api.upsertActionsVariable(owner, repo, AppConfig.stopVariable, runId.toString());

  Future<void> cancel({required String owner, required String repo, required int runId}) =>
      _api.cancelRun(owner, repo, runId);

  Future<List<ArtifactInfo>> artifacts({
    required String owner,
    required String repo,
    required int runId,
  }) =>
      _api.listArtifacts(owner, repo, runId);

  Future<void> downloadArtifact({
    required String owner,
    required String repo,
    required ArtifactInfo artifact,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) =>
      _api.downloadArtifact(
        owner: owner,
        repo: repo,
        artifactId: artifact.id,
        savePath: savePath,
        onProgress: onProgress,
      );

  WorkflowJob? _pickJob(List<WorkflowJob> jobs) {
    if (jobs.isEmpty) return null;
    for (final job in jobs) {
      if (job.labels.contains(AppConfig.runnerLabel)) return job;
    }
    return jobs.first;
  }
}

class RepoSecretsStatus {
  const RepoSecretsStatus({required this.password, required this.tailscale});

  /// null = unknown (no permission to read secret metadata).
  final bool? password;
  final bool? tailscale;
}
