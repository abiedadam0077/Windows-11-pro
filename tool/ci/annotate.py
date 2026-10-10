#!/usr/bin/env python3
"""Publishes analyzer findings and a log tail as GitHub annotations.

Usage: annotate.py <log-file> <label>

Annotations are visible in the check-run API even when the raw job log cannot be downloaded.
"""
import re
import sys

FINDING = re.compile(r'^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+(\S+?):(\d+):(\d+)\s+•\s+(\S+)\s*$')


def esc(text: str) -> str:
    return text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, label = sys.argv[1], sys.argv[2]
    with open(path, encoding='utf-8', errors='replace') as fh:
        text = fh.read()
    findings = 0
    for line in text.splitlines():
        m = FINDING.match(line)
        if not m:
            continue
        level, message, file_, lineno, col, rule = m.groups()
        command = {'error': 'error', 'warning': 'warning'}.get(level, 'notice')
        print(f'::{command} file={file_},line={lineno},col={col},title={label}: {rule}::{esc(message)}')
        findings += 1
    tail = text[-3000:]
    print(f'::notice title={label} output tail::{esc(tail)}')
    print(f'::notice title={label} summary::{findings} analyzer finding(s) annotated')


if __name__ == '__main__':
    main()
