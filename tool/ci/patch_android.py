#!/usr/bin/env python3
"""Applies WinPilot's Android customisations to a freshly generated `android/` folder.

Usage: patch_android.py <path-to-android-dir>

- Copies android_overrides/AndroidManifest.xml (INTERNET and notifications).
- Sets compileSdk to 36 (plugin AARs require it) and minSdk to 23 (required by flutter_secure_storage on current plugin versions).
- Enables core library desugaring (flutter_local_notifications 17 requires it on Android).
- Adds a `release` signing config that reads the stable keystore from environment variables
  (WINPILOT_KEYSTORE_PATH / WINPILOT_KEYSTORE_PASSWORD / WINPILOT_KEY_ALIAS / WINPILOT_KEY_PASSWORD).
  Without those variables the release build is NOT signed with a debug key: the CI workflow
  refuses to run before the build when the secrets are missing, and verifies the signature afterwards.

Fails loudly if a Gradle file does not have the expected shape, so CI never
ships an APK that was patched only partially.
"""
import pathlib
import re
import shutil
import sys

DESUGAR_LIB = 'com.android.tools:desugar_jdk_libs:2.1.4'
MIN_SDK = 23
# Current plugin AARs (file_picker, flutter_plugin_android_lifecycle) are compiled against API 36.
COMPILE_SDK = 36
ROOT = pathlib.Path(__file__).resolve().parent.parent.parent


def patch_manifest(android_dir: pathlib.Path) -> None:
    target = android_dir / 'app/src/main/AndroidManifest.xml'
    if not target.exists():
        sys.exit(f'missing manifest: {target}')
    shutil.copyfile(ROOT / 'android_overrides/AndroidManifest.xml', target)
    print(f'manifest replaced: {target}')


def patch_gradle(android_dir: pathlib.Path) -> None:
    kts = android_dir / 'app/build.gradle.kts'
    groovy = android_dir / 'app/build.gradle'
    if kts.exists():
        path, text = kts, kts.read_text(encoding='utf-8')
        text, n = re.subn(r'minSdk\s*=\s*flutter\.minSdkVersion', f'minSdk = {MIN_SDK}', text)
        if n != 1:
            sys.exit('minSdk assignment not found in build.gradle.kts')
        text, n = re.subn(r'compileSdk\s*=\s*flutter\.compileSdkVersion', f'compileSdk = {COMPILE_SDK}', text)
        if n != 1:
            sys.exit('compileSdk assignment not found in build.gradle.kts')
        text, n = re.subn(r'(compileOptions\s*\{)',
                          r'\1\n        isCoreLibraryDesugaringEnabled = true', text, count=1)
        if n != 1:
            sys.exit('compileOptions block not found in build.gradle.kts')
        text = text.rstrip() + f'\n\ndependencies {{\n    coreLibraryDesugaring("{DESUGAR_LIB}")\n}}\n'
    elif groovy.exists():
        path, text = groovy, groovy.read_text(encoding='utf-8')
        text, n = re.subn(r'minSdkVersion\s+flutter\.minSdkVersion', f'minSdkVersion {MIN_SDK}', text)
        if n != 1:
            sys.exit('minSdkVersion not found in build.gradle')
        text, n = re.subn(r'compileSdkVersion\s+flutter\.compileSdkVersion', f'compileSdkVersion {COMPILE_SDK}', text)
        if n != 1:
            sys.exit('compileSdkVersion not found in build.gradle')
        text, n = re.subn(r'(compileOptions\s*\{)',
                          r'\1\n        coreLibraryDesugaringEnabled true', text, count=1)
        if n != 1:
            sys.exit('compileOptions block not found in build.gradle')
        text = text.rstrip() + f"\n\ndependencies {{\n    coreLibraryDesugaring '{DESUGAR_LIB}'\n}}\n"
    else:
        sys.exit('no app/build.gradle(.kts) found')
    path.write_text(text, encoding='utf-8')
    print(f'gradle patched: {path}')


ROOT_KTS_BLOCK = """// WinPilot (tool/ci/patch_android.py): plugin AARs such as file_picker are compiled against an
// older API level; AAR metadata checks then fail. Force every subproject onto COMPILE_SDK.
// This block is placed before the template's evaluationDependsOn(":app") so projects are not yet evaluated.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder {
            "compileSdkVersion"(%d)
        }
    }
}

""" % COMPILE_SDK

ROOT_GROOVY_BLOCK = """// WinPilot (tool/ci/patch_android.py): force every subproject onto compileSdk %d.
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty('android')) {
            project.android.compileSdkVersion %d
        }
    }
}

""" % (COMPILE_SDK, COMPILE_SDK)


def patch_root_gradle(android_dir: pathlib.Path) -> None:
    kts = android_dir / 'build.gradle.kts'
    groovy = android_dir / 'build.gradle'
    if kts.exists():
        path, block = kts, ROOT_KTS_BLOCK
    elif groovy.exists():
        path, block = groovy, ROOT_GROOVY_BLOCK
    else:
        sys.exit('no root android/build.gradle(.kts) found')
    text = path.read_text(encoding='utf-8')
    if 'WinPilot (tool/ci/patch_android.py)' not in text:
        path.write_text(block + text, encoding='utf-8')
    print(f'root gradle patched: {path}')


SIGNING_KTS = '''    signingConfigs {
        create("release") {
            // Stable WinPilot release key, provided by GitHub Actions secrets (see README).
            // Never a debug key and never a per-build key: that would break in-place updates.
            System.getenv("WINPILOT_KEYSTORE_PATH")?.let { ksPath ->
                storeFile = file(ksPath)
                storePassword = System.getenv("WINPILOT_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("WINPILOT_KEY_ALIAS")
                keyPassword = System.getenv("WINPILOT_KEY_PASSWORD")
            }
        }
    }
'''

SIGNING_GROOVY = '''    signingConfigs {
        release {
            // Stable WinPilot release key from GitHub Actions secrets (see README).
            if (System.getenv('WINPILOT_KEYSTORE_PATH')) {
                storeFile file(System.getenv('WINPILOT_KEYSTORE_PATH'))
                storePassword System.getenv('WINPILOT_KEYSTORE_PASSWORD')
                keyAlias System.getenv('WINPILOT_KEY_ALIAS')
                keyPassword System.getenv('WINPILOT_KEY_PASSWORD')
            }
        }
    }
'''


def patch_signing(android_dir: pathlib.Path) -> None:
    kts = android_dir / 'app/build.gradle.kts'
    groovy = android_dir / 'app/build.gradle'
    if kts.exists():
        path, text = kts, kts.read_text(encoding='utf-8')
        text, n = re.subn(r'^android\s*\{\n', 'android {\n' + SIGNING_KTS, text, count=1, flags=re.M)
        if n != 1:
            sys.exit('android { block not found in build.gradle.kts')
        text, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                          'signingConfig = signingConfigs.getByName("release")', text)
        if n != 1:
            sys.exit('debug signingConfig assignment not found in build.gradle.kts')
    elif groovy.exists():
        path, text = groovy, groovy.read_text(encoding='utf-8')
        text, n = re.subn(r'^android\s*\{\n', 'android {\n' + SIGNING_GROOVY, text, count=1, flags=re.M)
        if n != 1:
            sys.exit('android { block not found in build.gradle')
        text, n = re.subn(r'signingConfig\s+signingConfigs\.debug', 'signingConfig signingConfigs.release', text)
        if n != 1:
            sys.exit('debug signingConfig assignment not found in build.gradle')
    else:
        sys.exit('no app/build.gradle(.kts) found')
    path.write_text(text, encoding='utf-8')
    print(f'release signing patched: {path}')


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    android_dir = pathlib.Path(sys.argv[1]).resolve()
    patch_manifest(android_dir)
    patch_gradle(android_dir)
    patch_signing(android_dir)
    patch_root_gradle(android_dir)


if __name__ == '__main__':
    main()
