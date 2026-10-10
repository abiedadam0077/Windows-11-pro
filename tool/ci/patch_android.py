#!/usr/bin/env python3
"""Applies WinPilot's Android customisations to a freshly generated `android/` folder.

Usage: patch_android.py <path-to-android-dir>

- Copies android_overrides/AndroidManifest.xml (INTERNET, notifications, OAuth intent filter).
- Sets minSdk to 23 (required by flutter_secure_storage / app_links on current plugin versions).
- Enables core library desugaring (flutter_local_notifications 17 requires it on Android).

Fails loudly if a Gradle file does not have the expected shape, so CI never
ships an APK that was patched only partially.
"""
import pathlib
import re
import shutil
import sys

DESUGAR_LIB = 'com.android.tools:desugar_jdk_libs:2.1.4'
MIN_SDK = 23
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
        text, n = re.subn(r'(compileOptions\s*\{)',
                          r'\1\n        coreLibraryDesugaringEnabled true', text, count=1)
        if n != 1:
            sys.exit('compileOptions block not found in build.gradle')
        text = text.rstrip() + f"\n\ndependencies {{\n    coreLibraryDesugaring '{DESUGAR_LIB}'\n}}\n"
    else:
        sys.exit('no app/build.gradle(.kts) found')
    path.write_text(text, encoding='utf-8')
    print(f'gradle patched: {path}')


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    android_dir = pathlib.Path(sys.argv[1]).resolve()
    patch_manifest(android_dir)
    patch_gradle(android_dir)


if __name__ == '__main__':
    main()
