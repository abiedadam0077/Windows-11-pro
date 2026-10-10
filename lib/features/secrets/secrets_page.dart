import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../data/services/github_secrets.dart';
import '../../state/providers.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Writes the per-repository Actions secrets from inside the app.
///
/// Secret values are sealed on-device and sent to GitHub; they are never
/// stored by the app, written to logs, or placed in URLs.
class SecretsPage extends ConsumerStatefulWidget {
  const SecretsPage({super.key});

  @override
  ConsumerState<SecretsPage> createState() => _SecretsPageState();
}

enum _SecretState { idle, saving, saved, failed }

class _SecretsPageState extends ConsumerState<SecretsPage> {
  late final TextEditingController _user;
  final _password = TextEditingController();
  final _backup = TextEditingController();
  bool _showPassword = false;
  bool _showBackup = false;
  _SecretState _winState = _SecretState.idle;
  _SecretState _backupState = _SecretState.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(text: ref.read(settingsProvider).windowsUser);
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _backup.dispose();
    super.dispose();
  }

  String? get _repoFullName => ref.read(settingsProvider).defaultRepo;

  Future<void> _save(AppStrings s) async {
    final repo = _repoFullName;
    if (repo == null || !repo.contains('/')) {
      setState(() => _error = s.t('secrets_need_repo'));
      return;
    }
    final username = _user.text.trim();
    final winPw = _password.text;
    final backupPw = _backup.text;
    if (!Validators.isValidWindowsUsername(username)) {
      setState(() => _error = s.t('secrets_username_invalid'));
      return;
    }
    if (PasswordPolicy.violations(winPw, username: username).isNotEmpty) {
      setState(() => _error = s.t('secrets_password_weak'));
      return;
    }
    if (PasswordPolicy.violations(backupPw).isNotEmpty) {
      setState(() => _error = s.t('secrets_backup_weak'));
      return;
    }
    final parts = repo.split('/');
    final writer = GitHubSecretsWriter(ref.read(githubApiProvider));
    setState(() {
      _error = null;
      _winState = _SecretState.saving;
      _backupState = _SecretState.saving;
    });
    // Windows password first; the backup password is written only if this succeeds.
    final winOk = await _writeOne(writer, parts, 'WINPILOT_WIN_PASSWORD', winPw, (st) {
      setState(() => _winState = st);
    });
    if (!mounted) return;
    if (!winOk) return;
    await _writeOne(writer, parts, 'BACKUP_PASSWORD', backupPw, (st) {
      setState(() => _backupState = st);
    });
  }

  Future<bool> _writeOne(
    GitHubSecretsWriter writer,
    List<String> parts,
    String name,
    String value,
    void Function(_SecretState) onState,
  ) async {
    try {
      final verified = await writer.write(
        owner: parts[0],
        repo: parts.sublist(1).join('/'),
        name: name,
        value: value,
      );
      if (!mounted) return false;
      if (verified) {
        onState(_SecretState.saved);
        return true;
      }
      onState(_SecretState.failed);
      setState(() => _error = AppStrings.of(context).t('secrets_not_verified', {'name': name}));
      return false;
    } on AppFailure catch (e) {
      if (!mounted) return false;
      onState(_SecretState.failed);
      final key = e.kind == FailureKind.forbidden
          ? 'secrets_forbidden'
          : e.kind == FailureKind.network || e.kind == FailureKind.timeout
              ? 'secrets_network'
              : 'secrets_generic';
      setState(() => _error = AppStrings.of(context).t(key, {'name': name}));
      return false;
    }
  }

  void _generate(TextEditingController target) {
    setState(() {
      target.text = PasswordPolicy.generate(length: 24);
      _showPassword = true;
      _showBackup = true;
    });
  }

  Future<void> _copy(String value, AppStrings s) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showAppSnack(context, s.t('secrets_copied'));
  }

  Widget _statusChip(AppStrings s, _SecretState st) {
    final (label, color, icon) = switch (st) {
      _SecretState.idle => (s.t('secrets_status_idle'), AppColors.textMuted, Icons.hourglass_empty_rounded),
      _SecretState.saving => (s.t('secrets_status_saving'), AppColors.cyan, Icons.sync_rounded),
      _SecretState.saved => (s.t('secrets_status_saved'), AppColors.success, Icons.verified_rounded),
      _SecretState.failed => (s.t('secrets_status_failed'), AppColors.danger, Icons.error_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final repo = ref.watch(settingsProvider.select((x) => x.defaultRepo));
    final busy = _winState == _SecretState.saving || _backupState == _SecretState.saving;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('secrets_title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            GlassCard(
              child: Row(children: [
                const Icon(Icons.lock_outline_rounded, color: AppColors.cyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    repo == null ? s.t('secrets_need_repo') : s.t('secrets_repo_target', {'repo': repo}),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            SectionTitle(s.t('secrets_windows_section')),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _user,
                  enabled: !busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: s.t('secrets_username')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !busy,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: s.t('secrets_password'),
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? s.t('secrets_hide') : s.t('secrets_show'),
                      icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _generate(_password),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: Text(s.t('secrets_generate')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(_password.text, s),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(s.t('secrets_copy')),
                  ),
                ]),
                const SizedBox(height: 8),
                _statusChip(s, _winState),
              ]),
            ),
            const SizedBox(height: 12),
            SectionTitle(s.t('secrets_backup_section')),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('secrets_backup_desc'), style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 12),
                TextField(
                  controller: _backup,
                  enabled: !busy,
                  obscureText: !_showBackup,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: s.t('secrets_backup_password'),
                    suffixIcon: IconButton(
                      tooltip: _showBackup ? s.t('secrets_hide') : s.t('secrets_show'),
                      icon: Icon(_showBackup ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                      onPressed: () => setState(() => _showBackup = !_showBackup),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _generate(_backup),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: Text(s.t('secrets_generate')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(_backup.text, s),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(s.t('secrets_copy')),
                  ),
                ]),
                const SizedBox(height: 8),
                _statusChip(s, _backupState),
                const SizedBox(height: 8),
                Text(s.t('secrets_backup_warning'), style: const TextStyle(color: AppColors.warning, fontSize: 12)),
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: busy ? s.t('secrets_saving') : s.t('secrets_save'),
              onPressed: busy ? null : () => _save(s),
            ),
            const SizedBox(height: 12),
            Text(s.t('secrets_roles'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
