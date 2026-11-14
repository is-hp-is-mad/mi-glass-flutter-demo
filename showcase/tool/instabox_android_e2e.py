#!/usr/bin/env python3
"""InstaBox persistent Android box lifecycle and E2E verification for HyperGlass / mi-glass.

Reuses the persistent InstaBox container pattern from Flutify CI:
- Reuses a single named persistent InstaBox Android container (`create` as a
  persistent box, `resume`/`start` on later runs, `suspend` after cleanup).
- Never destroys the container (`instabox rm`) and never uninstalls packages.
- Installs & launches both the native Android Sample APK (`com.hyperos.glass.sample`)
  and the Flutter Showcase APK (`com.example.hyper_glass`), verifies process
  liveness & zero fatal crashes, captures screenshots + dumpsys gfxinfo + logcat,
  and writes `metrics.json` and `summary.md`.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from typing import Any

BOX_OUT_DIR = "/data/home/miglass_e2e_out"
BOX_STAGE_DIR = "/data/home/miglass_stage"

TARGETS: dict[str, dict[str, str]] = {
    "sample": {
        "name": "HyperGlass Native Sample",
        "package_id": "com.hyperos.glass.sample",
        "activity": "com.hyperos.glass.sample/.SampleActivity",
    },
    "showcase": {
        "name": "MiGlass Flutter Showcase",
        "package_id": "com.example.hyper_glass",
        "activity": "com.example.hyper_glass/.MainActivity",
    },
}


class Runner:
    """Thin command execution abstraction to enable deterministic unit tests."""

    def run(
        self,
        cmd: list[str],
        *,
        check: bool = True,
        timeout: int = 120,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        proc = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=timeout,
            env=merged_env,
        )
        if check and proc.returncode != 0:
            raise RuntimeError(
                f"Command failed ({proc.returncode}): {' '.join(cmd)}\n"
                f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
            )
        return proc

    def exec_box(
        self,
        box: str,
        shell_cmd: str,
        *,
        check: bool = True,
        timeout: int = 180,
    ) -> subprocess.CompletedProcess[str]:
        exec_timeout = min(max(int(timeout), 1), 600)
        return self.run(
            [
                "instabox",
                "exec",
                box,
                "--timeout",
                str(exec_timeout),
                "--",
                "sh",
                "-c",
                shell_cmd,
            ],
            check=check,
            timeout=timeout + 30,
        )


def box_exists_in_listing(raw_output: str, box_name: str) -> bool:
    """Determine if `box_name` exists from `instabox ls --json` or plain `instabox ls`."""
    text = (raw_output or "").strip()
    if not text:
        return False
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        for line in text.splitlines():
            tokens = [tok.strip() for tok in line.split() if tok.strip()]
            if box_name in tokens:
                return True
        return False

    items: list[Any] = []
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict):
        for key in ("machines", "boxes", "items", "data"):
            val = data.get(key)
            if isinstance(val, list):
                items = val
                break
    for item in items:
        if isinstance(item, str) and item == box_name:
            return True
        if isinstance(item, dict):
            for key in ("name", "id", "box_name"):
                if item.get(key) == box_name:
                    return True
    return False


def ensure_box_ready(runner: Runner, box_name: str) -> str:
    """Create persistent Android box if missing, else resume/start it and wait for Android boot.

    Returns `'created'` or `'reused'`.
    """
    exists = False
    ls_json = runner.run(["instabox", "ls", "--json"], check=False, timeout=60)
    if ls_json.returncode == 0 and ls_json.stdout.strip():
        exists = box_exists_in_listing(ls_json.stdout, box_name)
    else:
        ls_plain = runner.run(["instabox", "ls"], check=True, timeout=60)
        exists = box_exists_in_listing(ls_plain.stdout, box_name)

    state = "reused" if exists else "created"
    if not exists:
        print(f"[instabox] Creating persistent Android box '{box_name}' (no --delete-after)...")
        runner.run(
            ["instabox", "create", "--name", box_name, "--template", "android"],
            check=True,
            timeout=300,
        )
    else:
        print(f"[instabox] Reusing persistent Android box '{box_name}'...")
        res = runner.run(["instabox", "resume", box_name], check=False, timeout=180)
        if res.returncode != 0:
            runner.run(["instabox", "start", box_name], check=False, timeout=180)
        runner.exec_box(box_name, "true", check=True, timeout=120)

    boot_cmd = """
set -euo pipefail
for i in $(seq 1 90); do
  if [ "$(docker exec instabox-android getprop sys.boot_completed 2>/dev/null || true)" = "1" ]; then
    break
  fi
  sleep 2
done
[ "$(docker exec instabox-android getprop sys.boot_completed 2>/dev/null || true)" = "1" ]
if ! adb devices | grep -qE '\\tdevice$'; then
  adb connect 127.0.0.1:5555 || true
  adb wait-for-device
fi
adb devices
"""
    runner.exec_box(box_name, boot_cmd, check=True, timeout=240)
    return state


def clean_environment(
    runner: Runner,
    box_name: str,
    *,
    suspend: bool = False,
) -> None:
    """Clean temporary E2E & staging state on the box without uninstalling apps or destroying the box."""
    stop_cmds = "\n".join(
        f"adb shell am force-stop {shlex.quote(t['package_id'])} >/dev/null 2>&1 || true"
        for t in TARGETS.values()
    )
    clean_cmd = f"""
set +e
{stop_cmds}
adb shell rm -f /data/local/tmp/miglass_*.png >/dev/null 2>&1 || true
rm -rf {shlex.quote(BOX_OUT_DIR)} {shlex.quote(BOX_STAGE_DIR)} >/dev/null 2>&1 || true
"""
    runner.exec_box(box_name, clean_cmd, check=False, timeout=120)
    if suspend:
        runner.run(["instabox", "suspend", box_name], check=False, timeout=120)


def parse_gfxinfo_summary(gfx_text: str) -> dict[str, int | None]:
    """Extract total frames and janky frames from `adb shell dumpsys gfxinfo`."""
    total_match = re.search(r"Total frames rendered:\s*(\d+)", gfx_text or "")
    janky_match = re.search(r"Janky frames:\s*(\d+)", gfx_text or "")
    return {
        "total_frames": int(total_match.group(1)) if total_match else None,
        "janky_frames": int(janky_match.group(1)) if janky_match else None,
    }


def _pull_box_out(runner: Runner, box_name: str, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    runner.run(
        ["instabox", "pull", box_name, BOX_OUT_DIR, str(out_dir)],
        check=True,
        timeout=180,
    )
    nested = out_dir / Path(BOX_OUT_DIR).name
    if nested.is_dir():
        for child in nested.iterdir():
            dest = out_dir / child.name
            if dest.exists():
                if dest.is_dir():
                    shutil.rmtree(dest)
                else:
                    dest.unlink()
            shutil.move(str(child), str(dest))
        nested.rmdir()


def verify_apk_on_box(
    runner: Runner,
    box_name: str,
    target_key: str,
    apk_path: Path,
    *,
    settle_seconds: int = 6,
) -> dict[str, Any]:
    """Stage, install, launch, screenshot, and inspect one APK inside the InstaBox container."""
    if not apk_path.is_file():
        raise FileNotFoundError(f"APK not found for {target_key}: {apk_path}")

    spec = TARGETS[target_key]
    pkg = spec["package_id"]
    activity = spec["activity"]
    remote_apk = f"{BOX_STAGE_DIR}/{target_key}.apk"
    device_png = f"/data/local/tmp/miglass_{target_key}.png"

    runner.exec_box(
        box_name,
        f"mkdir -p {shlex.quote(BOX_STAGE_DIR)} {shlex.quote(BOX_OUT_DIR)}",
        check=True,
        timeout=60,
    )
    runner.run(
        ["instabox", "cp", "-p", str(apk_path), f"{box_name}:{remote_apk}"],
        check=True,
        timeout=180,
    )

    run_cmd = f"""
set -euo pipefail
adb shell am force-stop {shlex.quote(pkg)} >/dev/null 2>&1 || true
adb install -r -d {shlex.quote(remote_apk)}
adb logcat -c
adb shell dumpsys gfxinfo {shlex.quote(pkg)} reset >/dev/null 2>&1 || true
adb shell am start -W -n {shlex.quote(activity)}
sleep {int(settle_seconds)}
PID=$(adb shell pidof {shlex.quote(pkg)} | tr -d '\\r\\n' || true)
echo "MIGLASS_PID=${{PID}}"
test -n "$PID"
adb shell screencap -p {shlex.quote(device_png)}
adb pull {shlex.quote(device_png)} {shlex.quote(f'{BOX_OUT_DIR}/{target_key}.png')}
adb shell dumpsys gfxinfo {shlex.quote(pkg)} > {shlex.quote(f'{BOX_OUT_DIR}/{target_key}_gfxinfo.txt')} || true
adb logcat -d -t 500 > {shlex.quote(f'{BOX_OUT_DIR}/{target_key}_logcat.txt')} || true
adb shell am force-stop {shlex.quote(pkg)} >/dev/null 2>&1 || true
"""
    proc = runner.exec_box(box_name, run_cmd, check=True, timeout=240)
    pid_match = re.search(r"MIGLASS_PID=(\S+)", proc.stdout or "")
    return {
        "target": target_key,
        "name": spec["name"],
        "package_id": pkg,
        "activity": activity,
        "apk": apk_path.name,
        "pid": pid_match.group(1) if pid_match else None,
        "screenshot": f"{target_key}.png",
    }


def _evaluate_outputs(out_dir: Path, results: list[dict[str, Any]]) -> dict[str, Any]:
    all_ok = True
    for item in results:
        key = item["target"]
        png_path = out_dir / f"{key}.png"
        log_path = out_dir / f"{key}_logcat.txt"
        gfx_path = out_dir / f"{key}_gfxinfo.txt"

        png_bytes = png_path.stat().st_size if png_path.is_file() else 0
        log_text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
        gfx_text = gfx_path.read_text(encoding="utf-8", errors="replace") if gfx_path.is_file() else ""

        fatal = "FATAL EXCEPTION" in log_text or f"Process: {item['package_id']}, PID:" in log_text
        gfx = parse_gfxinfo_summary(gfx_text)
        passed = bool(item.get("pid")) and png_bytes > 1024 and not fatal
        if not passed:
            all_ok = False

        item["png_bytes"] = png_bytes
        item["fatal_crash"] = fatal
        item["gfxinfo"] = gfx
        item["passed"] = passed

    return {"passed": all_ok, "targets": results}


def write_summary_markdown(metrics: dict[str, Any], out_dir: Path) -> None:
    lines = [
        "## InstaBox Android E2E Verification Summary",
        "",
        f"- **Box**: `{metrics.get('box_name')}` ({metrics.get('box_state')})",
        f"- **Overall**: {'PASSED' if metrics.get('passed') else 'FAILED'}",
        "",
        "| Target | Package | PID | Screenshot (bytes) | Fatal Crash | Total / Janky Frames | Status |",
        "| --- | --- | --- | ---: | --- | --- | --- |",
    ]
    for item in metrics.get("targets", []):
        gfx = item.get("gfxinfo") or {}
        frames = f"{gfx.get('total_frames', '-')} / {gfx.get('janky_frames', '-')}"
        status = "PASS" if item.get("passed") else "FAIL"
        lines.append(
            f"| {item['name']} | `{item['package_id']}` | `{item.get('pid') or '-'}` | "
            f"{item.get('png_bytes', 0)} | {item.get('fatal_crash')} | {frames} | **{status}** |"
        )
    (out_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_android_e2e(
    *,
    box_name: str,
    out_dir: Path,
    sample_apk: Path | None = None,
    showcase_apk: Path | None = None,
    settle_seconds: int = 6,
    runner: Runner | None = None,
) -> dict[str, Any]:
    if not sample_apk and not showcase_apk:
        raise ValueError("At least one of --sample-apk or --showcase-apk must be provided.")

    r = runner or Runner()
    box_state = ensure_box_ready(r, box_name)
    clean_environment(r, box_name, suspend=False)

    targets_to_run: list[tuple[str, Path]] = []
    if sample_apk:
        targets_to_run.append(("sample", sample_apk))
    if showcase_apk:
        targets_to_run.append(("showcase", showcase_apk))

    raw_results = [
        verify_apk_on_box(r, box_name, key, apk, settle_seconds=settle_seconds)
        for key, apk in targets_to_run
    ]
    _pull_box_out(r, box_name, out_dir)
    evaluated = _evaluate_outputs(out_dir, raw_results)
    metrics: dict[str, Any] = {
        "box_name": box_name,
        "box_state": box_state,
        **evaluated,
    }
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    write_summary_markdown(metrics, out_dir)
    return metrics


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="InstaBox Android E2E runner for HyperGlass / mi-glass.")
    sub = parser.add_subparsers(dest="command", required=True)

    run_p = sub.add_parser("run", help="Install & verify APKs on persistent InstaBox Android box.")
    run_p.add_argument("--box", required=True, help="Persistent InstaBox container name.")
    run_p.add_argument("--sample-apk", type=Path, default=None, help="Path to HyperGlass sample APK.")
    run_p.add_argument("--showcase-apk", type=Path, default=None, help="Path to Flutter showcase APK.")
    run_p.add_argument("--out-dir", type=Path, required=True, help="Output directory for screenshots & reports.")
    run_p.add_argument("--settle-seconds", type=int, default=6, help="Seconds to wait after launch before screencap.")

    clean_p = sub.add_parser("cleanup", help="Clean temporary E2E artifacts and suspend box.")
    clean_p.add_argument("--box", required=True, help="Persistent InstaBox container name.")

    args = parser.parse_args(argv)
    if args.command == "cleanup":
        clean_environment(Runner(), args.box, suspend=True)
        return 0

    metrics = run_android_e2e(
        box_name=args.box,
        out_dir=args.out_dir,
        sample_apk=args.sample_apk,
        showcase_apk=args.showcase_apk,
        settle_seconds=args.settle_seconds,
    )
    return 0 if metrics.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
