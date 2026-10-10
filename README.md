# WinPilot

WinPilot is an Android app (Flutter, Arabic and English, RTL/LTR, Material 3) that sets up and monitors
**temporary Windows 11 ARM64 sessions** that run on **GitHub Actions** (`runs-on: windows-11-arm`).
It does not start or manage any VPS or other provider, and it never substitutes Windows Server or x64 runners.

## What it does

- Signs in with GitHub using the OAuth **Device Flow**: WinPilot shows a short code, you approve it on github.com, and
  the app polls until approval, denial, expiry or cancellation. No client secret, no redirect URI and no password are used.
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

## Download the APK

Each build is published as a normal GitHub Release, tagged `v<version>-build.<run>`, with
`WinPilot-release.apk`, its `.sha256` file and `winpilot-update.json`. The newest one is the **latest release**:
<https://github.com/abiedadam0077/Windows-11-pro/releases/latest>. Verify the SHA-256 before installing.
Inside the app, **Settings → About** shows the installed version and checks for a newer APK.

## One-time setup (maintainer)

1. **Create a GitHub OAuth App** (GitHub → Settings → Developer settings → OAuth Apps → New OAuth App).
   - Homepage URL: any valid URL (for example `https://github.com/abiedadam0077/Windows-11-pro`).
   - Authorization callback URL: any valid URL. Device Flow does not use it.
   - Tick **Enable Device Flow** and save. Without this, sign-in fails with a clear message.
   - Do **not** copy or paste the client secret anywhere in WinPilot. Only the Client ID is used.
2. **Client ID** – add it as an Actions variable `WINPILOT_GITHUB_CLIENT_ID` in this repository (used at build
   time), or paste it in the app under Settings → GitHub OAuth Client ID. The Client ID is public.
3. **Release signing key (required for every build).** Run once on your own computer, with a JDK and `gh` logged in:
   ```bash
   tool/release/create_release_keystore.sh abiedadam0077/Windows-11-pro
   ```
   It creates a 4096-bit PKCS12 key outside the repository and sets the GitHub Actions secrets
   `WINPILOT_KEYSTORE_B64`, `WINPILOT_KEYSTORE_PASSWORD`, `WINPILOT_KEY_PASSWORD` and `WINPILOT_KEY_ALIAS`.
   **Back up the printed folder.** Losing this key means Android will not accept in-place updates any more.
   The build fails on purpose when these secrets are missing; it never falls back to a debug key.
4. **Per-session secrets** – in each repository you run sessions in, add these GitHub Actions secrets. Never put them
   in the app, the APK, settings or logs:
   - `BACKUP_PASSWORD` – encrypts and decrypts the Windows disk backups (required; at least 16 characters). Losing it makes existing backups unreadable.
   - `ACCESS_PASSWORD` – the password of the Windows account AND of the protected browser page (required; 12+ characters with upper, lower, digit and symbol).
   - `TS_AUTHKEY` – Tailscale auth key (optional; only needed for RDP over Tailscale).
   The app writes these secrets through the GitHub API (encrypted with the repository public key, libsodium sealed box). It then checks that each name exists. Old names such as `WINPILOT_WIN_PASSWORD` and `TAILSCALE_AUTHKEY` are not used any more and can be deleted.

## Updating the app and signing

- The application id is `com.winpilot.winpilot` and never changes.
- Every build is signed with the **same** release key, so Android can install a newer build over an older one.
  Your settings, history and sign-in are kept, because the app runs data migrations and never resets on update.
- `versionCode` is the GitHub run number (always increasing). `versionName` comes from `pubspec.yaml` (`x.y.z`).
- Android always asks you to confirm the install. WinPilot never installs silently.
- **One-time exception:** builds made before this key existed were signed by a temporary key. Android cannot
  update those in place. Uninstall the old WinPilot once, then install the new APK. Local app data is removed by
  that uninstall; GitHub data is not affected.

## Build

GitHub Actions builds the APK (`.github/workflows/build-android.yml`):

- Generates the Android project with `flutter create --platforms=android`, then applies `android_overrides/` and
  `tool/ci/patch_android.py` (INTERNET and notification permissions, release signing from secrets, minSdk 23, core library desugaring).
- Runs `tool/check_i18n_keys.py`, `flutter analyze`, `flutter test`, then `flutter build apk --release --build-name --build-number`.
- Verifies package name, version, INTERNET permission and app label with `aapt`, and checks with `apksigner` that the
  signature matches the release keystore and is not the debug key.
- Writes the SHA-256 file and `winpilot-update.json`, uploads them as an artifact, and on push publishes the GitHub Release.

The APK is signed with the stable WinPilot release key. It is suitable for sideloading; it is not a Play Store build.

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
