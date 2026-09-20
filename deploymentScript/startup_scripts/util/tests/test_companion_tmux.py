"""Bind SSH tmux to the systemd companion session (socket under /tmp)."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

UTIL = Path(__file__).resolve().parents[1]
STARTUP = UTIL.parent
BIND = UTIL / "companion_tmux.sh"


class TestCompanionTmuxBind(unittest.TestCase):
    def _run_bind(self, tmux_script: str, extra_env: dict[str, str] | None = None):
        with tempfile.TemporaryDirectory() as td:
            fake = Path(td) / "tmux"
            fake.write_text("#!/bin/bash\n" + tmux_script)
            fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
            env = os.environ.copy()
            env["PATH"] = f"{td}:{env['PATH']}"
            env["XDG_RUNTIME_DIR"] = "/run/user/1000"
            env.pop("TMUX_TMPDIR", None)
            if extra_env:
                env.update(extra_env)
            snippet = (
                f'source {BIND} && companion_tmux_bind_session catswarm_sim; '
                r'printf %s "${TMUX_TMPDIR:-}"; printf ,; printf %s "${XDG_RUNTIME_DIR:-}"'
            )
            return subprocess.run(
                ["bash", "-c", snippet],
                capture_output=True,
                text=True,
                env=env,
            )

    def test_bind_script_exists(self):
        self.assertTrue(BIND.is_file(), f"missing {BIND}")

    def test_binds_tmp_when_xdg_server_empty(self):
        r = self._run_bind(
            """
if [ "${TMUX_TMPDIR:-}" = /tmp ] && [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  exit 0
fi
exit 1
"""
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "/tmp,")

    def test_keeps_xdg_when_session_already_visible(self):
        r = self._run_bind("exit 0\n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, ",/run/user/1000")

    def test_switch_rtk_sources_bind(self):
        text = (STARTUP / "switch_rtk_WIFI_RF.sh").read_text()
        self.assertIn("companion_tmux.sh", text)
        self.assertIn("companion_tmux_bind_session", text)


class TestCompanionTmuxPipeSession(unittest.TestCase):
    def test_pipe_session_function_exists(self):
        snippet = f"source {BIND} && declare -F companion_tmux_pipe_session"
        r = subprocess.run(["bash", "-c", snippet], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("companion_tmux_pipe_session", r.stdout)

    def test_pipe_pane_dash_o_twice_and_creates_log_dir(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            fake = root / "tmux"
            capture = root / "tmux.args"
            log_dir = root / "RL" / "logs" / "tmux"
            fake.write_text(
                "#!/bin/bash\n"
                f"printf '%s\\n' \"$*\" >> '{capture}'\n"
                'if [ "$1" = list-panes ]; then\n'
                "  printf '%s\\n' 'catswarm_sim:0.0' 'catswarm_sim:0.1'\n"
                "fi\n"
                "exit 0\n"
            )
            fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
            env = os.environ.copy()
            env["PATH"] = f"{root}:{env['PATH']}"
            snippet = (
                f"source {BIND} && companion_tmux_pipe_session catswarm_sim '{log_dir}'"
            )
            r = subprocess.run(
                ["bash", "-c", snippet],
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(log_dir.is_dir(), f"missing log dir {log_dir}")
            logged = capture.read_text() if capture.is_file() else ""
            pipe_lines = [ln for ln in logged.splitlines() if "pipe-pane" in ln.split()]
            self.assertEqual(len(pipe_lines), 2, logged)
            for ln in pipe_lines:
                self.assertIn("-o", ln.split(), ln)

    def test_start_script_pipes_after_vio(self):
        text = (STARTUP / "start_companion_drone_tmux.sh").read_text()
        self.assertIn("companion_tmux.sh", text)
        vio = text.find("companion_vio_start_in_tmux")
        pipe = text.find("companion_tmux_pipe_session")
        self.assertNotEqual(vio, -1, "missing companion_vio_start_in_tmux")
        self.assertNotEqual(pipe, -1, "missing companion_tmux_pipe_session")
        self.assertGreater(
            pipe,
            vio,
            "companion_tmux_pipe_session must run after companion_vio_start_in_tmux",
        )


class TestCompanionJournaldPersistent(unittest.TestCase):
    def test_install_boot_writes_persistent_journald_dropin(self):
        text = (
            STARTUP.parent / "deploy_pi5" / "install-companion-boot.sh"
        ).read_text()
        self.assertIn("/etc/systemd/journald.d/companion-persistent.conf", text)
        self.assertIn("Storage=persistent", text)
        drop = text.find("Storage=persistent")
        enable = text.find("systemctl enable companion-drone.service")
        restart = text.find("systemctl restart companion-drone.service")
        self.assertNotEqual(enable, -1)
        self.assertNotEqual(restart, -1)
        self.assertGreater(enable, drop, "journald drop-in must precede enable")
        self.assertGreater(restart, drop, "journald drop-in must precede restart")


if __name__ == "__main__":
    unittest.main()
