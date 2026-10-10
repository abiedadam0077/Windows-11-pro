import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../models/github_models.dart';
import '../../models/session_models.dart';
import '../../state/providers.dart';
import '../../state/session_state.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Five-step launch wizard: repository, Windows account, network, review, launch.
/// Nothing is sent to GitHub until the explicit confirmation on step 4.
class SetupWizardPage extends ConsumerStatefulWidget {
  const SetupWizardPage({super.key});

  @override
  ConsumerState<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends ConsumerState<SetupWizardPage> {
  static const _lastStep = 4;
  int _step = 0;

  final _userCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _showPw = false;
  bool _enableRdp = false;
  bool _useTs = false;
  int _minutes = AppConfig.defaultSessionMinutes;
  bool _confirmed = false;
  bool _checkingSecrets = false;
  bool _installing = false;
  bool? _pwSecretPresent;
  bool? _tsSecretPresent;
  AppFailure? _launchFailure;

  @override
  void initState() {
    super.initState();
    final st = ref.read(settingsProvider);
    _userCtrl.text = st.windowsUser;
    _useTs = st.useTailscale;
    _minutes = st.sessionMinutes;
    _userCtrl.addListener(() => setState(() {}));
    _pwCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  RepoSummary? _repoFor(List<RepoSummary> repos, String? fullName) {
    if (fullName == null) return null;
    for (final r in repos) {
      if (r.fullName == fullName) return r;
    }
    return null;
  }

  bool? _effectivePwSecret(RepoReadiness? r) => _pwSecretPresent ?? r?.passwordSecret;

  List<String> _pwViolations() =>
      PasswordPolicy.violations(_pwCtrl.text, username: _userCtrl.text.trim());

  /// Localization keys of everything still blocking the launch.
  List<String> _missing(RepoSummary? repo, RepoReadiness? r) {
    final out = <String>[];
    if (repo == null) {
      out.add('setup_missing_repo');
      return out;
    }
    if (r == null) return out;
    if (!r.workflowExists) {
      out.add('setup_missing_workflow');
    } else if (!r.workflowCurrent) {
      out.add('setup_outdated_workflow');
    }
    if (r.blockers.isNotEmpty) out.add('setup_missing_blockers');
    if (!Validators.isValidWindowsUsername(_userCtrl.text.trim())) out.add('setup_missing_user');
    if (_enableRdp) {
      if (_pwViolations().isNotEmpty) out.add('setup_missing_password');
      if (_effectivePwSecret(r) == false) out.add('setup_missing_secrets');
    }
    return out;
  }

  bool _canContinue(RepoSummary? repo, RepoReadiness? r) {
    return switch (_step) {
      0 => repo != null && r != null && r.canStart && r.workflowCurrent,
      1 => Validators.isValidWindowsUsername(_userCtrl.text.trim()) &&
          (!_enableRdp || (_pwViolations().isEmpty && _effectivePwSecret(r) != false)),
      2 => true,
      3 => _confirmed && _missing(repo, r).isEmpty,
      _ => false,
    };
  }

  Future<void> _checkSecrets(RepoSummary repo) async {
    setState(() => _checkingSecrets = true);
    try {
      final status = await ref.read(githubRepositoryProvider).secretsStatus(repo);
      if (!mounted) return;
      setState(() {
        _pwSecretPresent = status.password;
        _tsSecretPresent = status.tailscale;
      });
    } on AppFailure catch (e) {
      if (mounted) showAppSnack(context, e.detail ?? context.s.t(e.titleKey));
    } finally {
      if (mounted) setState(() => _checkingSecrets = false);
    }
  }

  Future<void> _installWorkflow(RepoSummary repo, RepoReadiness r) async {
    final s = context.s;
    final template = await ref.read(workflowTemplateProvider.future);
    final existing = r.workflowFile;
    if (existing != null && existing.content.trim() == template.trim()) {
      if (mounted) showAppSnack(context, s.t('setup_workflow_identical'));
      ref.invalidate(repoReadinessProvider(repo));
      return;
    }
    if (existing != null) {
      if (!mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.t('setup_workflow_replace_title')),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('setup_workflow_replace_body')),
                const SizedBox(height: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        existing.content.length > 4000
                            ? '${existing.content.substring(0, 4000)}\n…'
                            : existing.content,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('setup_workflow_replace_confirm')),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    setState(() => _installing = true);
    try {
      await ref.read(githubRepositoryProvider).installWorkflow(
            repo: repo,
            path: ref.read(settingsProvider).workflowPath,
            content: template,
            existingSha: existing?.sha,
          );
      ref.invalidate(repoReadinessProvider(repo));
      if (mounted) {
        showAppSnack(context, s.t('setup_workflow_installed', {'branch': repo.defaultBranch}));
      }
    } on AppFailure catch (e) {
      if (mounted) showAppSnack(context, s.t(e.titleKey));
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _launch(RepoSummary repo) async {
    ref.read(settingsProvider.notifier)
      ..setWindowsUser(_userCtrl.text.trim())
      ..setUseTailscale(_useTs)
      ..setSessionMinutes(_minutes);
    final st = ref.read(settingsProvider);
    setState(() => _launchFailure = null);
    final ok = await ref.read(sessionProvider.notifier).startSession(
          repoFullName: repo.fullName,
          branch: repo.defaultBranch,
          request: SessionRequest(
            workflowPath: st.workflowPath,
            windowsUser: _userCtrl.text.trim(),
            enableRdp: _enableRdp,
            useTailscale: _useTs && _tsSecretPresent == true,
            sessionMinutes: _minutes,
          ),
        );
    if (!mounted) return;
    final runId = ref.read(sessionProvider).active?.runId;
    if (ok && runId != null) {
      context.go('/session/$runId');
      return;
    }
    setState(() {
      _launchFailure = ref.read(sessionProvider).failure ?? const AppFailure(FailureKind.unknown);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final settings = ref.watch(settingsProvider);
    final reposAsync = ref.watch(repositoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('setup_title'))),
      body: reposAsync.when(
        loading: () => const LoadingPlaceholder(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: ErrorPanel(
            failure: e is AppFailure ? e : const AppFailure(FailureKind.unknown),
            onRetry: () => ref.invalidate(repositoriesProvider),
          ),
        ),
        data: (repos) {
          final repo = _repoFor(repos, settings.defaultRepo);
          final rAsync = repo == null ? null : ref.watch(repoReadinessProvider(repo));
          final readiness = rAsync?.valueOrNull;
          final canContinue = _canContinue(repo, readiness);
          final missing = _missing(repo, readiness);

          return Column(
            children: [
              _StepHeader(
                current: _step,
                labels: [
                  s.t('setup_step_repo'),
                  s.t('setup_step_account'),
                  s.t('setup_step_network'),
                  s.t('setup_step_review'),
                  s.t('setup_step_launch'),
                ],
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  child: ListView(
                    key: ValueKey(_step),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                    children: switch (_step) {
                      0 => _stepRepo(repo, rAsync),
                      1 => _stepAccount(repo, readiness),
                      2 => _stepNetwork(repo, readiness),
                      3 => _stepReview(repo, readiness, missing),
                      _ => _stepLaunch(repo),
                    },
                  ),
                ),
              ),
              if (_step < _lastStep)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    child: Row(
                      children: [
                        if (_step > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _step--),
                              child: Text(s.t('setup_back')),
                            ),
                          ),
                        if (_step > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: GradientButton(
                            label: _step == 3 ? s.t('setup_review_start') : s.t('setup_next'),
                            icon: _step == 3 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                            onPressed: canContinue
                                ? () {
                                    if (_step == 3) {
                                      setState(() => _step = _lastStep);
                                      if (repo != null) _launch(repo);
                                    } else {
                                      setState(() => _step++);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ step 0

  List<Widget> _stepRepo(RepoSummary? repo, AsyncValue<RepoReadiness>? rAsync) {
    final s = context.s;
    final theme = Theme.of(context);
    return [
      SectionTitle(s.t('setup_repo_section')),
      GlassCard(
        child: repo == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('setup_repo_none')),
                  const SizedBox(height: 12),
                  GradientButton(
                    label: s.t('setup_repo_pick'),
                    icon: Icons.folder_open_rounded,
                    onPressed: () => context.push('/repos'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(repo.isPrivate ? Icons.lock_rounded : Icons.public_rounded, color: AppColors.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(repo.fullName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  InfoRow(label: s.t('repo_visibility_private'), value: repo.isPrivate ? s.t('yes') : s.t('no')),
                  InfoRow(label: s.t('setup_review_branch'), value: repo.defaultBranch),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/repos'),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(s.t('setup_repo_pick')),
                  ),
                ],
              ),
      ),
      if (repo != null && rAsync != null)
        rAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(children: [
              Text(s.t('setup_checking')),
              const SizedBox(height: 10),
              const SkeletonBox(height: 60, radius: 16),
              const SizedBox(height: 10),
              const SkeletonBox(height: 60, radius: 16),
            ]),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.only(top: 14),
            child: ErrorPanel(
              failure: e is AppFailure ? e : const AppFailure(FailureKind.unknown),
              onRetry: () => ref.invalidate(repoReadinessProvider(repo)),
            ),
          ),
          data: (r) => _readinessView(repo, r),
        ),
      SectionTitle(s.t('setup_arch_section')),
      GlassCard(
        glow: AppColors.cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.memory_rounded, color: AppColors.cyan),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('setup_arch_value'), style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            Text(s.t('setup_arch_note'),
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.5)),
          ],
        ),
      ),
    ];
  }

  Widget _readinessView(RepoSummary repo, RepoReadiness r) {
    final s = context.s;
    final theme = Theme.of(context);
    String secretText(String name, bool? v) => v == null
        ? s.t('setup_secret_unknown', {'name': name})
        : v
            ? s.t('setup_secret_present', {'name': name})
            : s.t('setup_secret_missing', {'name': name});

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(s.t('setup_restrictions_section')),
          GlassCard(
            child: Column(
              children: [
                _check(
                  r.actionsEnabled,
                  r.actionsEnabled == true ? s.t('setup_actions_on') : s.t('setup_actions_unknown'),
                ),
                _check(r.workflowCurrent, r.workflowCurrent
                    ? s.t('setup_workflow_found', {'path': ref.read(settingsProvider).workflowPath})
                    : r.workflowExists
                        ? s.t('setup_workflow_outdated', {'path': ref.read(settingsProvider).workflowPath})
                        : s.t('setup_workflow_missing', {'path': ref.read(settingsProvider).workflowPath})),
                _check(
                  r.passwordSecret,
                  secretText(AppConfig.accessPasswordSecret, r.passwordSecret),
                ),
                _check(
                  r.tailscaleSecret,
                  secretText(AppConfig.tailscaleAuthKeySecret, r.tailscaleSecret),
                ),
              ],
            ),
          ),
          for (final key in r.blockers) _Notice(text: s.t(key), color: AppColors.danger),
          for (final key in r.warnings) _Notice(text: s.t(key), color: AppColors.warning),
          if (!r.workflowCurrent) ...[
            const SizedBox(height: 12),
            GradientButton(
              label: s.t(r.workflowExists ? 'setup_workflow_update' : 'setup_workflow_install'),
              icon: Icons.upload_file_rounded,
              loading: _installing,
              onPressed: _installing || !r.canStart ? null : () => _installWorkflow(repo, r),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              s.t('setup_secret_check'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _check(bool? ok, String text) {
    final color = ok == null
        ? AppColors.warning
        : ok
            ? AppColors.success
            : AppColors.danger;
    final icon = ok == null
        ? Icons.help_outline_rounded
        : ok
            ? Icons.check_circle_rounded
            : Icons.cancel_rounded;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ step 1

  List<Widget> _stepAccount(RepoSummary? repo, RepoReadiness? r) {
    final s = context.s;
    final theme = Theme.of(context);
    final user = _userCtrl.text.trim();
    final userOk = Validators.isValidWindowsUsername(user);
    final violations = _pwViolations();
    final rules = ['pw_rule_length', 'pw_rule_upper', 'pw_rule_lower', 'pw_rule_digit', 'pw_rule_symbol', 'pw_rule_username'];
    final pwSecret = _effectivePwSecret(r);

    return [
      SectionTitle(s.t('setup_account_title')),
      GlassCard(child: Text(s.t('setup_account_desc'), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5))),
      const SizedBox(height: 14),
      TextField(
        controller: _userCtrl,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: s.t('setup_user_label'),
          helperText: s.t('setup_user_hint'),
          errorText: user.isNotEmpty && !userOk ? s.t('setup_user_invalid') : null,
          prefixIcon: const Icon(Icons.person_outline_rounded),
        ),
      ),
      const SizedBox(height: 14),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _enableRdp,
        title: Text(s.t('setup_rdp_toggle')),
        subtitle: Text(s.t('setup_rdp_toggle_desc')),
        onChanged: (v) => setState(() => _enableRdp = v),
      ),
      if (_enableRdp) ...[
        TextField(
          controller: _pwCtrl,
          obscureText: !_showPw,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: s.t('setup_password_label'),
            prefixIcon: const Icon(Icons.key_rounded),
            suffixIcon: IconButton(
              tooltip: _showPw ? s.t('setup_password_hide') : s.t('setup_password_show'),
              icon: Icon(_showPw ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _showPw = !_showPw),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                _pwCtrl.text = PasswordPolicy.generate();
                setState(() => _showPw = true);
              },
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(s.t('setup_password_generate')),
            ),
            if (_pwCtrl.text.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _pwCtrl.text));
                  if (mounted) showAppSnack(context, s.t('copied'));
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(s.t('copy')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(s.t('setup_password_rules'), style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final rule in rules)
          _check(
            !violations.contains(rule) && _pwCtrl.text.isNotEmpty ? true : (_pwCtrl.text.isEmpty ? null : false),
            s.t(rule),
          ),
        const SizedBox(height: 10),
        GlassCard(
          glow: AppColors.violet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('setup_password_secure_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(s.t('setup_password_secure_body'),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5, color: AppColors.textMuted)),
              const SizedBox(height: 12),
              _check(
                pwSecret,
                pwSecret == null
                    ? s.t('setup_secret_unknown', {'name': AppConfig.accessPasswordSecret})
                    : pwSecret
                        ? s.t('setup_secret_present', {'name': AppConfig.accessPasswordSecret})
                        : s.t('setup_secret_missing', {'name': AppConfig.accessPasswordSecret}),
              ),
              if (repo != null)
                OutlinedButton.icon(
                  onPressed: _checkingSecrets ? null : () => _checkSecrets(repo),
                  icon: _checkingSecrets
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_outlined),
                  label: Text(s.t('setup_secret_check')),
                ),
            ],
          ),
        ),
        if (pwSecret == false)
          _Notice(text: s.t('setup_rdp_needs_secret'), color: AppColors.danger),
      ] else
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(s.t('setup_rdp_off_note'),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        ),
    ];
  }

  // ------------------------------------------------------------ step 2

  List<Widget> _stepNetwork(RepoSummary? repo, RepoReadiness? r) {
    final s = context.s;
    final theme = Theme.of(context);
    final tsSecret = _tsSecretPresent ?? r?.tailscaleSecret;
    return [
      SectionTitle(s.t('setup_network_title')),
      GlassCard(child: Text(s.t('setup_network_desc'), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5))),
      const SizedBox(height: 10),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _useTs,
        title: Text(s.t('setup_ts_toggle')),
        subtitle: Text(s.t('setup_ts_toggle_desc')),
        // Tailscale can only be enabled once the TS_AUTHKEY secret exists in the repository.
        onChanged: _tsSecretPresent == true ? (v) => setState(() => _useTs = v) : null,
      ),
      if (_useTs) ...[
        GlassCard(
          glow: AppColors.cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.t('setup_ts_steps_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(s.t('setup_ts_steps'), style: theme.textTheme.bodySmall?.copyWith(height: 1.6)),
              const SizedBox(height: 10),
              _check(
                tsSecret,
                tsSecret == null
                    ? s.t('setup_secret_unknown', {'name': AppConfig.tailscaleAuthKeySecret})
                    : tsSecret
                        ? s.t('setup_secret_present', {'name': AppConfig.tailscaleAuthKeySecret})
                        : s.t('setup_secret_missing', {'name': AppConfig.tailscaleAuthKeySecret}),
              ),
              Text(s.t('setup_ts_phone_note'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ],
      SectionTitle(s.t('setup_minutes_label')),
      GlassCard(
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text(s.t('setup_minutes_value', {'m': '$_minutes'}),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            ]),
            Slider(
              value: _minutes.toDouble(),
              min: AppConfig.minSessionMinutes.toDouble(),
              max: AppConfig.maxSessionMinutes.toDouble(),
              divisions: (AppConfig.maxSessionMinutes - AppConfig.minSessionMinutes) ~/ 5,
              label: '$_minutes',
              onChanged: (v) => setState(() => _minutes = v.round()),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(s.t('setup_minutes_note'),
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------------ step 3

  List<Widget> _stepReview(RepoSummary? repo, RepoReadiness? r, List<String> missing) {
    final s = context.s;
    final theme = Theme.of(context);
    return [
      SectionTitle(s.t('setup_review_title')),
      GlassCard(child: Text(s.t('setup_review_desc'), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5))),
      const SizedBox(height: 12),
      GlassCard(
        child: Column(
          children: [
            InfoRow(label: s.t('setup_review_repo'), value: repo?.fullName ?? '—'),
            InfoRow(label: s.t('setup_review_system'), value: 'Windows 11'),
            InfoRow(label: s.t('setup_review_arch'), value: s.t('target_system_value')),
            InfoRow(label: s.t('setup_review_user'), value: _userCtrl.text.trim()),
            InfoRow(label: s.t('setup_review_rdp'), value: _enableRdp ? s.t('on') : s.t('off')),
            InfoRow(label: s.t('setup_review_tailscale'), value: _useTs ? s.t('on') : s.t('off')),
            InfoRow(label: s.t('setup_review_minutes'), value: s.t('setup_minutes_value', {'m': '$_minutes'})),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (missing.isEmpty)
        _Notice(text: s.t('setup_review_none_missing'), color: AppColors.success)
      else ...[
        Text(s.t('setup_review_missing'), style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final key in missing) _Notice(text: s.t(key), color: AppColors.danger),
      ],
      for (final key in r?.warnings ?? const <String>[])
        _Notice(text: s.t(key), color: AppColors.warning),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() => _step = 0),
        icon: const Icon(Icons.edit_rounded),
        label: Text('${s.t('setup_review_edit')}: ${s.t('setup_step_repo')}'),
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _confirmed,
        onChanged: (v) => setState(() => _confirmed = v ?? false),
        title: Text(s.t('setup_review_confirm_check')),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          OutlinedButton(onPressed: () => setState(() => _step = 1), child: Text(s.t('setup_step_account'))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => setState(() => _step = 2), child: Text(s.t('setup_step_network'))),
        ],
      ),
    ];
  }

  // ------------------------------------------------------------ step 4

  List<Widget> _stepLaunch(RepoSummary? repo) {
    final s = context.s;
    final failure = _launchFailure;
    if (failure == null) {
      return [
        const SizedBox(height: 40),
        const Center(child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3))),
        const SizedBox(height: 22),
        Center(child: Text(s.t('setup_launch_dispatching'), textAlign: TextAlign.center)),
      ];
    }
    return [
      SectionTitle(s.t('setup_launch_failed')),
      ErrorPanel(
        failure: failure,
        onRetry: repo == null ? null : () => _launch(repo),
      ),
      const SizedBox(height: 10),
      Text(s.t('setup_launch_hint'), style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => setState(() {
          _step = 3;
          _launchFailure = null;
        }),
        child: Text(s.t('setup_back')),
      ),
    ];
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current, required this.labels});

  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: i <= current ? AppColors.brandGradient : null,
                          color: i <= current ? null : theme.colorScheme.onSurface.withValues(alpha: 0.12),
                        ),
                        child: i < current
                            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                            : Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: i <= current ? Colors.white : theme.colorScheme.onSurface)),
                      ),
                      const SizedBox(height: 4),
                      Text(labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: i == current ? AppColors.cyan : AppColors.textMuted,
                            fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                          )),
                    ],
                  ),
                ),
                if (i < labels.length - 1)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Container(
                        height: 2,
                        color: i < current ? AppColors.electricBlue : theme.colorScheme.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(text),
      );
}
