/// Central, non-secret configuration.
///
/// Secrets (client secrets, Tailscale auth keys, Windows passwords) never live
/// in this file or in the APK. The OAuth *client ID* is public and can be
/// injected at build time with `--dart-define=GITHUB_CLIENT_ID=...` or entered
/// in Settings.
abstract final class AppConfig {
  static const appName = 'WinPilot';

  // OAuth: GitHub Device Flow. Needs only the public Client ID; no client
  // secret, no redirect URI, no custom URL scheme.
  static const oauthScopes = 'repo workflow read:user';
  // Public OAuth App Client ID (not a secret). A build-time define or the
  // Settings value overrides it.
  static const defaultClientId = String.fromEnvironment(
    'GITHUB_CLIENT_ID',
    defaultValue: 'Ov23lia2WyFusPFukYaK',
  );

  // GitHub endpoints.
  static const githubWebBase = 'https://github.com';
  static const githubApiBase = 'https://api.github.com';
  static const githubApiVersion = '2022-11-28';
  static const userAgent = 'WinPilot-Android/1.0';

  // Workflow configuration.
  static const defaultWorkflowPath = '.github/workflows/verify-windows-11.yml';
  static const workflowTemplateAsset = 'assets/workflows/verify-windows-11.yml';
  static const runnerLabel = 'ubuntu-latest';
  static const backupPasswordSecret = 'BACKUP_PASSWORD';
  static const windowsPasswordSecret = 'WINPILOT_WIN_PASSWORD';
  static const tailscaleAuthKeySecret = 'TS_AUTHKEY';

  // Session limits (bounded, documented to the user).
  static const defaultSessionMinutes = 30;
  static const minSessionMinutes = 5;
  static const maxSessionMinutes = 120;
  static const defaultWindowsUser = 'winpilot';

  // Polling and memory limits.
  static const pollInterval = Duration(seconds: 15);
  static const maxLogLines = 5000;
  static const logPageSize = 300;
  static const maxArtifactBytes = 150 * 1024 * 1024;
  static const maxStoredSessions = 30;
  static const expiryWarning = Duration(minutes: 5);
  static const runnerWaitWarning = Duration(minutes: 10);

  static const rdpPort = 3389;
  static const rdpClientPackage = 'com.microsoft.rdc.androidx';
  static const rdpClientStoreUrl =
      'https://play.google.com/store/apps/details?id=com.microsoft.rdc.androidx';
  static const tailscaleAdminKeysUrl =
      'https://login.tailscale.com/admin/settings/keys';
  static const notificationChannelId = 'winpilot_sessions';

  // Updates: published as GitHub Releases on this repository.
  static const releasesRepo = 'abiedadam0077/Windows-11-pro';
  static const updateManifestAsset = 'winpilot-update.json';
  static const releaseApkAsset = 'WinPilot-release.apk';
}
