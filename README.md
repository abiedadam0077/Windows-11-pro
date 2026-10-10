# WinPilot

WinPilot is an Android app (Flutter, Arabic and English, RTL/LTR, Material 3) that sets up and monitors
**temporary Windows 11 ARM64 sessions** that run on **GitHub Actions** (`runs-on: windows-11-arm`).
It does not start or manage any VPS or other provider, and it never substitutes Windows Server or x64 runners.

## What it does

- Signs in with GitHub using OAuth Authorization Code + PKCE. No client secret and no password are used in the app.
- Lists, searches, filters and creates repositories you can access.
- Checks a repository for the workflow file and installs `.github/workflows/verify-windows-11.yml` after you confirm any overwrite.
- Guides you through a five-step setup wizard, then dispatches the workflow and tracks the real run.
- Shows live job steps, runner-declared diagnostics, a bounded session timer, redacted logs and downloadable artifacts.
- Checks Tailscale IPs against `100.64.0.0/10` and runs a real TCP probe to port 3389 from the phone.
- Keeps local session history and optional notifications (only while the app is open).

## Limits (also shown in the app)

- The runner is **ephemeral**. Files, programs and settings are not kept after the session.
- A session is bounded to the length you choose (5–120 minutes).
- **A successful workflow run does not mean RDP is ready.** RDP is shown as ready only when the runner declares it,
  and the app separately checks port 3389 over Tailscale.
- `windows-11-arm` may be unavailable for private repositories depending on your GitHub plan. If no runner is
  available, the job waits in the queue and the app says so.

## One-time setup

1. **Create a GitHub OAuth App** (Settings → Developer settings → OAuth Apps). Use the callback URL
   `winpilot://oauth/callback`. Enable Device Flow only if you need it; the app uses PKCE.
2. **Client ID** – add it as an Actions variable `WINPILOT_GITHUB_CLIENT_ID` in this repository (used at build
   time), or paste it in the app under Settings → Advanced. The Client ID is public.
3. **Secrets** – in each repository you want to run sessions in, add these GitHub Actions secrets. Never put them
   in the app, the APK, settings or logs:
   - `WINPILOT_WIN_PASSWORD` – password for the Windows user (required only when RDP is enabled; 12+ characters with upper, lower, digit and symbol).
   - `TS_AUTHKEY` – Tailscale auth key (required only when Tailscale is enabled).
   The app only checks whether these secret names exist.

## Build

GitHub Actions builds the APK (`.github/workflows/build-android.yml`):

- Generates the Android project with `flutter create --platforms=android`, then applies `android_overrides/` and
  `tool/ci/patch_android.py` (INTERNET and notification permissions, OAuth intent filter, minSdk 23, core library desugaring).
- Runs `tool/check_i18n_keys.py`, `flutter analyze`, `flutter test`, then `flutter build apk --release`.
- Verifies package name, INTERNET permission and app label with `aapt`, writes a SHA-256 file and uploads the APK as an artifact.
- Manual runs with `publish_release` also create a GitHub pre-release containing the APK.

The APK is signed with the default debug signing key, so it is suitable for sideloading and testing, not for Play Store publication.

## Development

```bash
flutter pub get
flutter analyze
flutter test
python3 tool/check_i18n_keys.py
```

Non-secret configuration lives in `lib/core/config/app_config.dart`. The workflow template is `assets/workflows/verify-windows-11.yml`.

## Verification status

Local tooling in the development sandbox does not include the Flutter SDK, so analysis, tests and the APK build have
to run in GitHub Actions. Check the latest run of **Build Android APK** and the **Verify Windows 11 ARM64** workflow
for the actual results before relying on either.
