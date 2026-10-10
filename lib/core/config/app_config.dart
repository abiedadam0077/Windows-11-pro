/// Central, non-secret configuration.
///
/// Secrets (client secrets, Tailscale auth keys, Windows passwords) never live
/// in this file or in the APK. The OAuth *client ID* is public and can be
/// injected at build time with `--dart-define=GITHUB_CLIENT_ID=...` or entered
/// in Settings.
abstract final class AppConfig {
  static const appName = 'WinPilot';

  // OAuth (Authorization Code + PKCE, no client secret in the app).
  static const oauthCallbackScheme = 'winpilot';
  static const oauthRedirectUri = 'winpilot://oauth/callback';
  static const oauthScopes = 'repo workflow read:user';
  static const defaultClientId = String.fromEnvironment('GITHUB_CLIENT_ID');

  // GitHub endpoints.
  static const githubWebBase = 'https://github.com';
  static const githubApiBase = 'https://api.github.com';
  static const githubApiVersion = '2022-11-28';
  static const userAgent = 'WinPilot-Android/1.0';

  // Workflow configuration.
  static const defaultWorkflowPath = '.github/workflows/verify-windows-11.yml';
  static const workflowTemplateAsset = 'assets/workflows/verify-windows-11.yml';
  static const runnerLabel = 'windows-11-arm';
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
}
