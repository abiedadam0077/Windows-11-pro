#!/usr/bin/env python3
"""Writes winpilot-update.json for a release: version, versionCode, sha256, APK name.

Usage: make_update_manifest.py <apk> <version-name> <version-code> <out.json>

The app reads this file from the GitHub Release (see lib/data/services/update_service.dart).
"""
import hashlib
import json
import pathlib
import re
import sys
from datetime import datetime, timezone


def main() -> None:
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    apk, name, code, out = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
    if not re.fullmatch(r'\d{1,4}\.\d{1,4}\.\d{1,4}', name):
        sys.exit(f'version name must be x.y.z, got {name!r}')
    if not code.isdigit() or int(code) < 1:
        sys.exit(f'versionCode must be a positive integer, got {code!r}')
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    manifest = {
        'app': 'com.winpilot.winpilot',
        'version': name,
        'versionCode': int(code),
        'apk': apk.name,
        'sha256': digest,
        'minSdk': 23,
        'released': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    }
    out.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
