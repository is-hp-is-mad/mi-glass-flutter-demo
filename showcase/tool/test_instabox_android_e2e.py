"""Unit tests for InstaBox persistent Android E2E helper."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOL_DIR = Path(__file__).resolve().parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

import instabox_android_e2e as ib  # noqa: E402


class _FakeRunner(ib.Runner):
    def __init__(self, handler):
        self.calls: list[list[str]] = []
        self._handler = handler

    def run(self, cmd, *, check=True, timeout=120, env=None):
        self.calls.append(list(cmd))
        return self._handler(cmd)


class InstaBoxAndroidE2ETest(unittest.TestCase):
    def test_redact_sensitive_strips_emails_and_api_keys(self):
        raw = "Error for user alice.dev@example.com with key ibk_abc123XYZ999"
        redacted = ib.redact_sensitive(raw)
        self.assertNotIn("alice.dev@example.com", redacted)
        self.assertNotIn("ibk_abc123XYZ999", redacted)
        self.assertIn("<redacted-email>", redacted)
        self.assertIn("<redacted-key>", redacted)

    def test_ensure_box_ready_never_creates_by_default(self):
        def handler(cmd):
            if cmd[:2] == ["instabox", "ls"]:
                return subprocess.CompletedProcess(cmd, 0, stdout='{"boxes": []}', stderr="")
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        runner = _FakeRunner(handler)
        with self.assertRaises(RuntimeError):
            ib.ensure_box_ready(runner, "auto")
        self.assertFalse(any(c[:2] == ["instabox", "create"] for c in runner.calls))

    def test_ensure_box_ready_auto_picks_existing_android_box(self):
        def handler(cmd):
            if cmd[:2] == ["instabox", "ls"]:
                return subprocess.CompletedProcess(
                    cmd,
                    0,
                    stdout='{"boxes": [{"name": "flutify-e2e-android", "template": "android"}]}',
                    stderr="",
                )
            if cmd[:2] == ["instabox", "resume"]:
                return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="already stopped")
            return subprocess.CompletedProcess(cmd, 0, stdout="ok", stderr="")

        runner = _FakeRunner(handler)
        resolved, state = ib.ensure_box_ready(runner, "auto")
        self.assertEqual(resolved, "flutify-e2e-android")
        self.assertEqual(state, "reused")
        self.assertTrue(any(c[:3] == ["instabox", "resume", "flutify-e2e-android"] for c in runner.calls))
        self.assertTrue(any(c[:3] == ["instabox", "start", "flutify-e2e-android"] for c in runner.calls))
        self.assertFalse(any(c[:2] == ["instabox", "create"] for c in runner.calls))
        self.assertFalse(any(c[:2] == ["instabox", "rm"] for c in runner.calls))

    def test_clean_environment_suspends_without_destroying_or_uninstalling(self):
        def handler(cmd):
            if cmd[:2] == ["instabox", "ls"]:
                return subprocess.CompletedProcess(
                    cmd, 0, stdout='{"boxes": [{"name": "my-android-box", "template": "android"}]}', stderr=""
                )
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        runner = _FakeRunner(handler)
        ib.clean_environment(runner, "auto", suspend=True)
        joined = "\n".join(" ".join(c) for c in runner.calls)
        self.assertNotIn("instabox rm", joined)
        self.assertNotIn("adb uninstall", joined)
        self.assertIn("instabox suspend my-android-box", joined)

    def test_run_android_e2e_verifies_both_apks_and_writes_reports(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            sample_apk = tmp_path / "sample-debug.apk"
            showcase_apk = tmp_path / "app-release.apk"
            sample_apk.write_bytes(b"fake-sample-apk")
            showcase_apk.write_bytes(b"fake-showcase-apk")
            out_dir = tmp_path / "out"

            def handler(cmd):
                if cmd[:2] == ["instabox", "ls"]:
                    return subprocess.CompletedProcess(
                        cmd, 0, stdout='{"boxes": [{"name": "existing-android", "template": "android"}]}', stderr=""
                    )
                if cmd[:2] == ["instabox", "exec"]:
                    shell_cmd = cmd[-1]
                    if "MIGLASS_PID" in shell_cmd:
                        return subprocess.CompletedProcess(cmd, 0, stdout="MIGLASS_PID=4242\n", stderr="")
                    return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
                if cmd[:2] == ["instabox", "pull"]:
                    pulled = Path(cmd[4]) / Path(ib.BOX_OUT_DIR).name
                    pulled.mkdir(parents=True, exist_ok=True)
                    for key in ("sample", "showcase"):
                        (pulled / f"{key}.png").write_bytes(b"\x89PNG" + b"0" * 2048)
                        (pulled / f"{key}_logcat.txt").write_text("I/ActivityManager: Displayed\n", encoding="utf-8")
                        (pulled / f"{key}_gfxinfo.txt").write_text(
                            "Total frames rendered: 120\nJanky frames: 2 (1.67%)\n", encoding="utf-8"
                        )
                    return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
                return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

            runner = _FakeRunner(handler)
            metrics = ib.run_android_e2e(
                box_name="auto",
                out_dir=out_dir,
                sample_apk=sample_apk,
                showcase_apk=showcase_apk,
                settle_seconds=1,
                runner=runner,
            )

            self.assertTrue(metrics["passed"])
            self.assertEqual(metrics["box_name"], "existing-android")
            self.assertEqual(len(metrics["targets"]), 2)
            self.assertTrue((out_dir / "metrics.json").is_file())
            self.assertTrue((out_dir / "summary.md").is_file())
            saved = json.loads((out_dir / "metrics.json").read_text(encoding="utf-8"))
            self.assertTrue(saved["passed"])
            self.assertEqual(saved["targets"][0]["gfxinfo"]["total_frames"], 120)


if __name__ == "__main__":
    unittest.main()
