import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Non-sensitive preferences, legal pages, sign-out. No secrets are stored here.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _workflow;
  late final TextEditingController _user;
  late final TextEditingController _clientId;

  @override
  void initState() {
    super.initState();
    final st = ref.read(settingsProvider);
    _workflow = TextEditingController(text: st.workflowPath);
    _user = TextEditingController(text: st.windowsUser);
    _clientId = TextEditingController(text: st.clientId ?? '');
  }

  @override
  void dispose() {
    _workflow.dispose();
    _user.dispose();
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _toggleNotifications(bool value) async {
    final s = context.s;
    final ctrl = ref.read(settingsProvider.notifier);
    if (!value) {
      ctrl.setNotifications(false);
      return;
    }
    final granted = await ref.read(notificationServiceProvider).requestPermission();
    ctrl.setNotifications(granted);
    if (!granted && mounted) showAppSnack(context, s.t('settings_notif_denied'));
  }

  Future<void> _signOut() async {
    final s = context.s;
    final ok = await confirmDialog(
      context,
      title: s.t('settings_signout_title'),
      body: s.t('settings_signout_body'),
      confirmLabel: s.t('settings_signout'),
      destructive: true,
    );
    if (!ok) return;
    await ref.read(authProvider.notifier).signOut();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final st = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          SectionTitle(s.t('settings_account')),
          GlassCard(
            child: Column(
              children: [
                InfoRow(
                  label: s.t('settings_github'),
                  value: auth.user?.login ?? s.t('settings_not_connected'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(s.t('settings_signout')),
                ),
              ],
            ),
          ),
          SectionTitle(s.t('settings_appearance')),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('settings_language'), style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<LanguagePref>(
                  segments: [
                    ButtonSegment(value: LanguagePref.system, label: Text(s.t('settings_lang_system'))),
                    ButtonSegment(value: LanguagePref.english, label: const Text('English')),
                    ButtonSegment(value: LanguagePref.arabic, label: const Text('العربية')),
                  ],
                  selected: {st.language},
                  onSelectionChanged: (v) => ctrl.setLanguage(v.first),
                ),
                const SizedBox(height: 16),
                Text(s.t('settings_theme'), style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<ThemePref>(
                  segments: [
                    ButtonSegment(value: ThemePref.dark, label: Text(s.t('settings_theme_dark'))),
                    ButtonSegment(value: ThemePref.light, label: Text(s.t('settings_theme_light'))),
                    ButtonSegment(value: ThemePref.system, label: Text(s.t('settings_lang_system'))),
                  ],
                  selected: {st.theme},
                  onSelectionChanged: (v) => ctrl.setTheme(v.first),
                ),
              ],
            ),
          ),
          SectionTitle(s.t('settings_session_defaults')),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('settings_default_repo'), style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(st.defaultRepo ?? s.t('settings_none'), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.push('/repos'),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(s.t('setup_repo_pick')),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s.t('setup_user_label'),
                    helperText: s.t('setup_user_hint'),
                    errorText: _user.text.trim().isNotEmpty && !Validators.isValidWindowsUsername(_user.text.trim())
                        ? s.t('setup_user_invalid')
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() {});
                    if (Validators.isValidWindowsUsername(v.trim())) ctrl.setWindowsUser(v.trim());
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _workflow,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s.t('settings_workflow_path'),
                    helperText: s.t('settings_workflow_path_hint'),
                    errorText: _workflow.text.trim().isNotEmpty && !Validators.isValidWorkflowPath(_workflow.text.trim())
                        ? s.t('settings_workflow_path_invalid')
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() {});
                    if (Validators.isValidWorkflowPath(v.trim())) ctrl.setWorkflowPath(v.trim());
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  '${s.t('settings_default_minutes')}: ${s.t('setup_minutes_value', {'m': '${st.sessionMinutes}'})}',
                  style: theme.textTheme.labelLarge,
                ),
                Slider(
                  value: st.sessionMinutes.toDouble(),
                  min: AppConfig.minSessionMinutes.toDouble(),
                  max: AppConfig.maxSessionMinutes.toDouble(),
                  divisions: (AppConfig.maxSessionMinutes - AppConfig.minSessionMinutes) ~/ 5,
                  label: '${st.sessionMinutes}',
                  onChanged: (v) => ctrl.setSessionMinutes(v.round()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: st.useTailscale,
                  title: Text(s.t('setup_ts_toggle')),
                  subtitle: Text(s.t('setup_ts_toggle_desc')),
                  onChanged: ctrl.setUseTailscale,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: st.notificationsEnabled,
                  title: Text(s.t('settings_notifications')),
                  subtitle: Text(s.t('settings_notifications_desc')),
                  onChanged: _toggleNotifications,
                ),
              ],
            ),
          ),
          SectionTitle(s.t('settings_advanced')),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _clientId,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s.t('settings_client_id'),
                    helperText: s.t('settings_client_id_hint'),
                  ),
                  onSubmitted: (v) => ctrl.setClientId(v),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => ctrl.setClientId(_clientId.text),
                    child: Text(s.t('save')),
                  ),
                ),
                Text(s.t('settings_no_secret_note'),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          SectionTitle(s.t('settings_legal')),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(s.t('legal_privacy_title')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/legal/privacy'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.gavel_rounded),
                  title: Text(s.t('legal_terms_title')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/legal/terms'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(s.t('limits_title')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/legal/limits'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => Center(
              child: Text(
                snap.hasData
                    ? '${AppConfig.appName} ${snap.data!.version} (${snap.data!.buildNumber})'
                    : AppConfig.appName,
                style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
