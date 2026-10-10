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

/// Writes the three repository Actions secrets the VM workflow reads.
///
/// Values are sealed on the device and sent to GitHub. The app keeps them only
/// in the text fields of this screen; they are never logged, put in URLs, or
/// saved to local storage. Each secret is confirmed by GitHub before it is
/// shown as saved.
class SecretsPage extends ConsumerStatefulWidget {
  const SecretsPage({super.key});

  @override
  ConsumerState<SecretsPage> createState() => _SecretsPageState();
}

enum SecretSaveState { idle, saving, saved, failed }

const _kWinPassword = 'WINPILOT_WIN_PASSWORD';
const _kBackupPassword = 'BACKUP_PASSWORD';
const _kAccessPassword = 'ACCESS_PASSWORD';

class _SecretsPageState extends ConsumerState<SecretsPage> {
  late final TextEditingController _user;
  final _winPw = TextEditingController();
  final _backupPw = TextEditingController();
  final _accessPw = TextEditingController();
  final _shown = <String, bool>{
    _kWinPassword: false,
    _kBackupPassword: false,
    _kAccessPassword: false,
  };
  final _state = <String, SecretSaveState>{
    _kWinPassword: SecretSaveState.idle,
    _kBackupPassword: SecretSaveState.idle,
    _kAccessPassword: SecretSaveState.idle,
  };
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(text: ref.read(settingsProvider).windowsUser);
  }

  @override
  void dispose() {
    _user.dispose();
    _winPw.dispose();
    _backupPw.dispose();
    _accessPw.dispose();
    super.dispose();
  }

  TextEditingController _controller(String name) => switch (name) {
        _kWinPassword => _winPw,
        _kBackupPassword => _backupPw,
        _ => _accessPw,
      };

  /// Returns the localized problem with the current input, or null when ready.
  String? _validate(AppStrings s) {
    final repo = ref.read(settingsProvider).defaultRepo;
    if (repo == null || !repo.contains('/')) return s.t('secrets_need_repo');
    if (!Validators.isValidWindowsUsername(_user.text.trim())) {
      return s.t('secrets_username_invalid');
    }
    if (PasswordPolicy.violations(_winPw.text, username: _user.text.trim()).isNotEmpty) {
      return s.t('secrets_password_weak');
    }
    if (PasswordPolicy.violations(_backupPw.text).isNotEmpty) {
      return s.t('secrets_backup_weak');
    }
    if (PasswordPolicy.violations(_accessPw.text).isNotEmpty) {
      return s.t('secrets_access_weak');
    }
    return null;
  }

  Future<void> _save(AppStrings s) async {
    final problem = _validate(s);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final parts = ref.read(settingsProvider).defaultRepo!.split('/');
    final owner = parts.first;
    final repo = parts.sublist(1).join('/');
    final writer = GitHubSecretsWriter(ref.read(githubApiProvider));
    setState(() {
      _busy = true;
      _error = null;
    });
    // Only secrets not yet confirmed are written, so a retry does not re-send the others.
    for (final name in [_kWinPassword, _kBackupPassword, _kAccessPassword]) {
      if (_state[name] == SecretSaveState.saved) continue;
      setState(() => _state[name] = SecretSaveState.saving);
      String? failure;
      try {
        final verified = await writer.write(
          owner: owner,
          repo: repo,
          name: name,
          value: _controller(name).text,
        );
        if (!verified) failure = s.t('secrets_not_verified', {'name': name});
      } on AppFailure catch (e) {
        failure = switch (e.kind) {
          FailureKind.forbidden => s.t('secrets_forbidden', {'name': name}),
          FailureKind.network || FailureKind.timeout => s.t('secrets_network', {'name': name}),
          _ => s.t('secrets_generic', {'name': name}),
        };
      }
      if (!mounted) return;
      if (failure == null) {
        setState(() => _state[name] = SecretSaveState.saved);
      } else {
        // Stop at the first failure so the user sees exactly what is missing.
        setState(() {
          _state[name] = SecretSaveState.failed;
          _error = failure;
          _busy = false;
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showAppSnack(context, s.t('secrets_all_saved'));
  }

  void _generate(String name) {
    setState(() {
      _controller(name).text = PasswordPolicy.generate(length: 24);
      _shown[name] = true;
      _state[name] = SecretSaveState.idle;
    });
  }

  Future<void> _copy(String value, AppStrings s) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showAppSnack(context, s.t('secrets_copied'));
  }

  Widget _statusChip(AppStrings s, SecretSaveState st) {
    final (label, color, icon) = switch (st) {
      SecretSaveState.idle => (s.t('secrets_status_idle'), AppColors.textMuted, Icons.hourglass_empty_rounded),
      SecretSaveState.saving => (s.t('secrets_status_saving'), AppColors.cyan, Icons.sync_rounded),
      SecretSaveState.saved => (s.t('secrets_status_saved'), AppColors.success, Icons.verified_rounded),
      SecretSaveState.failed => (s.t('secrets_status_failed'), AppColors.danger, Icons.error_outline_rounded),
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

  Widget _passwordCard(
    AppStrings s, {
    required String name,
    required String title,
    required String description,
    String? warning,
  }) {
    final controller = _controller(name);
    final shown = _shown[name] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            _statusChip(s, _state[name] ?? SecretSaveState.idle),
          ]),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: !_busy,
            obscureText: !shown,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            onChanged: (_) => setState(() => _state[name] = SecretSaveState.idle),
            decoration: InputDecoration(
              labelText: name,
              suffixIcon: IconButton(
                tooltip: shown ? s.t('secrets_hide') : s.t('secrets_show'),
                icon: Icon(shown ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _shown[name] = !shown),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _generate(name),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: Text(s.t('secrets_generate')),
            ),
            OutlinedButton.icon(
              onPressed: () => _copy(controller.text, s),
              icon: const Icon(Icons.copy_rounded),
              label: Text(s.t('secrets_copy')),
            ),
          ]),
          if (warning != null) ...[
            const SizedBox(height: 8),
            Text(warning, style: const TextStyle(color: AppColors.warning, fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final repo = ref.watch(settingsProvider.select((x) => x.defaultRepo));
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
              child: TextField(
                controller: _user,
                enabled: !_busy,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: s.t('secrets_username')),
              ),
            ),
            const SizedBox(height: 12),
            _passwordCard(
              s,
              name: _kWinPassword,
              title: s.t('secrets_win_title'),
              description: s.t('secrets_win_desc'),
            ),
            SectionTitle(s.t('secrets_backup_section')),
            _passwordCard(
              s,
              name: _kBackupPassword,
              title: s.t('secrets_backup_title'),
              description: s.t('secrets_backup_desc'),
              warning: s.t('secrets_backup_warning'),
            ),
            SectionTitle(s.t('secrets_access_section')),
            _passwordCard(
              s,
              name: _kAccessPassword,
              title: s.t('secrets_access_title'),
              description: s.t('secrets_access_desc'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: _busy ? s.t('secrets_saving') : s.t('secrets_save'),
              onPressed: _busy ? null : () => _save(s),
            ),
            const SizedBox(height: 12),
            Text(s.t('secrets_roles'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
