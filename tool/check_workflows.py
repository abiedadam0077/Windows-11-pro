#!/usr/bin/env python3
"""Static checks for WinPilot workflows (run in CI).

- Both copies of the VM workflow (assets/ and .github/) must be identical.
- Every YAML file must parse; every `run:` block must pass `bash -n`
  after GitHub expressions are replaced with placeholders.
- Secrets must be read only through `env:` and never echoed unmasked.
- The VM workflow must reference the required secrets and keep the
  browser-access port bound to loopback.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
VM = ROOT / "assets/workflows/verify-windows-11.yml"
VM_COPY = ROOT / ".github/workflows/verify-windows-11.yml"
WORKFLOWS = sorted((ROOT / ".github/workflows").glob("*.yml"))
REQUIRED_SECRETS = ["BACKUP_PASSWORD", "ACCESS_PASSWORD"]
# TS_AUTHKEY is optional (Tailscale only). Old names must never reappear.
FORBIDDEN_SECRET_NAMES = ["WINPILOT_WIN_PASSWORD", "TAILSCALE_AUTHKEY"]
errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


def check_yaml_and_shell(path: Path) -> dict:
    doc = yaml.safe_load(path.read_text())
    if not isinstance(doc, dict) or "jobs" not in doc:
        fail(f"{path.name}: not a workflow (no jobs)")
        return doc or {}
    for job_id, job in doc["jobs"].items():
        for i, step in enumerate(job.get("steps", [])):
            run = step.get("run")
            if not run:
                continue
            script = re.sub(r"\$\{\{.*?\}\}", "PLACEHOLDER", run)
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
                f.write(script)
            res = subprocess.run(["bash", "-n", f.name], capture_output=True, text=True)
            if res.returncode != 0:
                fail(f"{path.name} job {job_id} step {i} ({step.get('name')}): bash -n: {res.stderr.strip()}")
            # Secrets must not be echoed or printed in clear.
            for line in run.splitlines():
                if re.search(r"\becho\b.*\$\{?(BACKUP_PASSWORD|ACCESS_PASSWORD|TS_AUTHKEY)\b", line) \
                   and "::add-mask::" not in line and "PASSWORD=" not in line:
                    fail(f"{path.name} job {job_id} step {i}: secret echoed: {line.strip()[:80]}")
    return doc


def main() -> int:
    for wf in WORKFLOWS:
        check_yaml_and_shell(wf)
    vm_doc = check_yaml_and_shell(VM)
    if VM.read_text() != VM_COPY.read_text():
        fail(".github/workflows/verify-windows-11.yml differs from assets/workflows/verify-windows-11.yml")
    text = VM.read_text()
    for name in REQUIRED_SECRETS:
        if f"secrets.{name}" not in text:
            fail(f"VM workflow does not read secrets.{name}")
    for name in FORBIDDEN_SECRET_NAMES:
        if name in text:
            fail(f"VM workflow still uses the old secret name {name}")
    if "secrets.TS_AUTHKEY" not in text:
        fail("VM workflow must read the optional secrets.TS_AUTHKEY")
    if "127.0.0.1:8006:8006" not in text:
        fail("VM workflow must bind the web viewer to 127.0.0.1 only")
    if "--env-file" not in text:
        fail("VM workflow must pass the Windows password with --env-file, not -e on the command line")
    on = vm_doc.get(True, vm_doc.get("on", {}))
    if "workflow_dispatch" not in on:
        fail("VM workflow must be workflow_dispatch only")
    for job_id, job in vm_doc["jobs"].items():
        if "timeout-minutes" not in job:
            fail(f"job {job_id} has no timeout-minutes")
    for err in errors:
        print("ERROR:", err)
    print(f"checked {len(WORKFLOWS)} workflow files; errors={len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
