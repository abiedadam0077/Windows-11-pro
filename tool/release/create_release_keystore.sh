#!/usr/bin/env bash
# One-time: create WinPilot's STABLE release signing key and store it in GitHub Actions secrets.
#
# Run this on YOUR computer (needs a JDK for `keytool`, and the GitHub CLI `gh` logged in
# as a repository admin). It never writes the keystore or passwords into the repository.
#
#   tool/release/create_release_keystore.sh abiedadam0077/Windows-11-pro
#
# BACK UP the generated folder (printed at the end). If you lose this key, Android will
# never accept an in-place update and users must uninstall first.
set -euo pipefail

REPO="${1:?usage: $0 <owner/repo>}"
command -v keytool >/dev/null || { echo "keytool (JDK 17+) is required" >&2; exit 1; }
command -v gh >/dev/null || { echo "GitHub CLI (gh) is required" >&2; exit 1; }

DIR="${WINPILOT_KEY_DIR:-$HOME/winpilot-release-key}"
if [ -e "$DIR/winpilot-release.p12" ]; then
  echo "A keystore already exists at $DIR. Refusing to overwrite it." >&2
  exit 1
fi
mkdir -p "$DIR"
chmod 700 "$DIR"

ALIAS="winpilot"
STORE_PASS="$(openssl rand -base64 33 | tr -d '/+=' | cut -c1-32)"
KEY_PASS="$STORE_PASS"   # PKCS12 keystores use one password for store and key.

keytool -genkeypair -v \
  -keystore "$DIR/winpilot-release.p12" -storetype PKCS12 \
  -storepass "$STORE_PASS" -alias "$ALIAS" -keypass "$KEY_PASS" \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -dname "CN=WinPilot, O=WinPilot, C=MA"

base64 -w0 "$DIR/winpilot-release.p12" > "$DIR/winpilot-release.p12.b64"
printf '%s' "$STORE_PASS" > "$DIR/store-password.txt"
printf '%s' "$ALIAS" > "$DIR/key-alias.txt"
chmod 600 "$DIR"/*

gh secret set WINPILOT_KEYSTORE_B64 --repo "$REPO" < "$DIR/winpilot-release.p12.b64"
gh secret set WINPILOT_KEYSTORE_PASSWORD --repo "$REPO" < "$DIR/store-password.txt"
gh secret set WINPILOT_KEY_PASSWORD --repo "$REPO" < "$DIR/store-password.txt"
gh secret set WINPILOT_KEY_ALIAS --repo "$REPO" < "$DIR/key-alias.txt"

echo
echo "Secrets set on $REPO: WINPILOT_KEYSTORE_B64, WINPILOT_KEYSTORE_PASSWORD, WINPILOT_KEY_PASSWORD, WINPILOT_KEY_ALIAS."
echo "Backup folder (keep it OUT of git and somewhere safe): $DIR"
echo "Certificate SHA-256 fingerprint (save this):"
keytool -list -v -keystore "$DIR/winpilot-release.p12" -storepass "$STORE_PASS" -alias "$ALIAS" \
  | grep -E 'SHA256:' || true
