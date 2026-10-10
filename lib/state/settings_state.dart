import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import 'providers.dart';

enum LanguagePref { system, arabic, english }

enum ThemePref { system, dark, light }

/// Non-sensitive user preferences. Nothing secret is stored here.
class AppSettings {
  const AppSettings({
    this.language = LanguagePref.system,
    this.theme = ThemePref.dark,
    this.notificationsEnabled = false,
    this.defaultRepo,
    this.workflowPath = AppConfig.defaultWorkflowPath,
    this.sessionMinutes = AppConfig.defaultSessionMinutes,
    this.useTailscale = false,
    this.windowsUser = AppConfig.defaultWindowsUser,
    this.clientId,
    this.onboardingDone = false,
  });

  final LanguagePref language;
  final ThemePref theme;
  final bool notificationsEnabled;
  final String? defaultRepo;
  final String workflowPath;
  final int sessionMinutes;
  final bool useTailscale;
  final String windowsUser;
  final String? clientId;
  final bool onboardingDone;

  Locale? get localeOverride => switch (language) {
        LanguagePref.arabic => const Locale('ar'),
        LanguagePref.english => const Locale('en'),
        LanguagePref.system => null,
      };

  ThemeMode get themeMode => switch (theme) {
        ThemePref.dark => ThemeMode.dark,
        ThemePref.light => ThemeMode.light,
        ThemePref.system => ThemeMode.system,
      };

  /// Client ID from Settings wins; otherwise the build-time define is used.
  String get effectiveClientId {
    final custom = clientId?.trim() ?? '';
    return custom.isNotEmpty ? custom : AppConfig.defaultClientId;
  }

  /// Language code used for notifications and other non-widget text.
  String resolveLanguageCode(String platformCode) => switch (language) {
        LanguagePref.arabic => 'ar',
        LanguagePref.english => 'en',
        LanguagePref.system => platformCode == 'ar' ? 'ar' : 'en',
      };

  AppSettings copyWith({
    LanguagePref? language,
    ThemePref? theme,
    bool? notificationsEnabled,
    String? defaultRepo,
    bool clearDefaultRepo = false,
    String? workflowPath,
    int? sessionMinutes,
    bool? useTailscale,
    String? windowsUser,
    String? clientId,
    bool clearClientId = false,
    bool? onboardingDone,
  }) =>
      AppSettings(
        language: language ?? this.language,
        theme: theme ?? this.theme,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        defaultRepo: clearDefaultRepo ? null : (defaultRepo ?? this.defaultRepo),
        workflowPath: workflowPath ?? this.workflowPath,
        sessionMinutes: sessionMinutes ?? this.sessionMinutes,
        useTailscale: useTailscale ?? this.useTailscale,
        windowsUser: windowsUser ?? this.windowsUser,
        clientId: clearClientId ? null : (clientId ?? this.clientId),
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );

  static AppSettings load(SharedPreferences p) {
    T byName<T extends Enum>(List<T> values, String? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    return AppSettings(
      language: byName(LanguagePref.values, p.getString('settings.language'), LanguagePref.system),
      theme: byName(ThemePref.values, p.getString('settings.theme'), ThemePref.dark),
      notificationsEnabled: p.getBool('settings.notifications') ?? false,
      defaultRepo: p.getString('settings.default_repo'),
      workflowPath: p.getString('settings.workflow_path') ?? AppConfig.defaultWorkflowPath,
      sessionMinutes: p.getInt('settings.session_minutes') ?? AppConfig.defaultSessionMinutes,
      useTailscale: p.getBool('settings.use_tailscale') ?? false,
      windowsUser: p.getString('settings.windows_user') ?? AppConfig.defaultWindowsUser,
      clientId: p.getString('settings.client_id'),
      onboardingDone: p.getBool('settings.onboarding_done') ?? false,
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setString('settings.language', language.name);
    await p.setString('settings.theme', theme.name);
    await p.setBool('settings.notifications', notificationsEnabled);
    await _setOrRemove(p, 'settings.default_repo', defaultRepo);
    await p.setString('settings.workflow_path', workflowPath);
    await p.setInt('settings.session_minutes', sessionMinutes);
    await p.setBool('settings.use_tailscale', useTailscale);
    await p.setString('settings.windows_user', windowsUser);
    await _setOrRemove(p, 'settings.client_id', clientId);
    await p.setBool('settings.onboarding_done', onboardingDone);
  }

  static Future<void> _setOrRemove(SharedPreferences p, String key, String? value) =>
      value == null || value.isEmpty ? p.remove(key) : p.setString(key, value);
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.read(sharedPreferencesProvider));

  void _set(AppSettings next) {
    state = next;
    unawaited(next.save(ref.read(sharedPreferencesProvider)));
  }

  void setLanguage(LanguagePref value) => _set(state.copyWith(language: value));

  void setTheme(ThemePref value) => _set(state.copyWith(theme: value));

  void setNotifications(bool enabled) => _set(state.copyWith(notificationsEnabled: enabled));

  void setDefaultRepo(String? fullName) => fullName == null
      ? _set(state.copyWith(clearDefaultRepo: true))
      : _set(state.copyWith(defaultRepo: fullName));

  void setWorkflowPath(String path) => _set(state.copyWith(workflowPath: path));

  void setSessionMinutes(int minutes) => _set(state.copyWith(
        sessionMinutes: minutes.clamp(AppConfig.minSessionMinutes, AppConfig.maxSessionMinutes),
      ));

  void setUseTailscale(bool value) => _set(state.copyWith(useTailscale: value));

  void setWindowsUser(String user) => _set(state.copyWith(windowsUser: user));

  void setClientId(String? value) {
    final trimmed = value?.trim() ?? '';
    _set(trimmed.isEmpty
        ? state.copyWith(clearClientId: true)
        : state.copyWith(clientId: trimmed));
  }

  void completeOnboarding() => _set(state.copyWith(onboardingDone: true));

  void resetPrivacyCache() {
    // Only non-sensitive preferences are reset; the token is managed by auth.
    _set(state.copyWith(clearDefaultRepo: true));
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
