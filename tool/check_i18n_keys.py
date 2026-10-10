#!/usr/bin/env python3
"""Verifies every i18n key referenced from Dart code exists in both dictionaries."""
import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STRINGS = ROOT / 'lib/core/i18n/app_strings.dart'


def dictionary(src: str, name: str) -> set[str]:
    start = src.index(f'const Map<String, String> {name} = {{')
    end = src.index('\n};', start)
    return set(re.findall(r"^\s*'([a-zA-Z0-9_]+)'\s*:", src[start:end], re.M))


def main() -> int:
    src = STRINGS.read_text(encoding='utf-8')
    en = dictionary(src, '_en')
    ar = dictionary(src, '_ar')
    used: set[str] = set()
    for path in (ROOT / 'lib').rglob('*.dart'):
        text = path.read_text(encoding='utf-8')
        # Literal keys passed to t(...) / s.t(...); also error keys built from failure kinds.
        used.update(re.findall(r"\bt\(\s*'([a-zA-Z0-9_]+)'", text))
    # Keys reached through variables are listed explicitly in the script's allow list.
    dynamic = {f'rdp_step_{i}' for i in range(1, 6)}
    dynamic |= {f'pw_rule_{r}' for r in ('length', 'upper', 'lower', 'digit', 'symbol', 'username')}
    dynamic |= {f'err_{k}_{p}' for k in ('network', 'unauthorized', 'forbidden', 'rateLimited', 'notFound',
                                         'validation', 'conflict', 'server', 'notConfigured', 'unsupported',
                                         'workflowMissing', 'runnerUnavailable', 'runNotFound', 'cancelled',
                                         'timeout', 'storage', 'unknown') for p in ('title', 'hint')}
    dynamic |= {'legal_privacy_title', 'legal_privacy_body', 'legal_terms_title', 'legal_terms_body',
                'limits_title', 'limits_body', 'limits_short', 'legal_updated'}
    used |= dynamic
    missing_en = sorted(used - en)
    missing_ar = sorted(used - ar)
    ok = not missing_en and not missing_ar
    for k in missing_en:
        print('missing in en:', k)
    for k in missing_ar:
        print('missing in ar:', k)
    print(f'checked {len(used)} keys; en={len(en)} ar={len(ar)}; ok={ok}')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
