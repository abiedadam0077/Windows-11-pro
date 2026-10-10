#!/usr/bin/env bash
# Usage: run_logged.sh <label> <command...>
# Runs the command, mirrors its output into an annotated log, and returns its exit code.
set -uo pipefail
label="$1"
shift
log="$(mktemp)"
"$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
python3 "$(dirname "$0")/annotate.py" "$log" "$label"
exit "$code"
