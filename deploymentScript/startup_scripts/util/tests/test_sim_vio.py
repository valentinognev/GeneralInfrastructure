import math
import re
import unittest
from pathlib import Path

from sim_vio_spec import (
    gz_pitch_cmd,
    iris_model_name,
    pitch_deg_to_joint_rad,
    sim_vio_skip_must_not_fail,
    sim_vio_window_name,
    vio_pitch_joint,
)

UTIL = Path(__file__).resolve().parents[1]


def _case_arm(text: str, name: str) -> str:
    marker = f"  {name})"
    start = text.index(marker)
    rest = text[start + len(marker) :]
    nxt = re.search(r"\n  [a-z*]+\)", rest)
    return rest[: nxt.start()] if nxt else rest


def _commands(arm: str) -> str:
    out = []
    for line in arm.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        out.append(s)
    return "\n".join(out)


class TestSimVio(unittest.TestCase):
    def test_window_name(self):
        self.assertEqual(sim_vio_window_name(1), "sim_vio_1")
        self.assertEqual(sim_vio_window_name(4), "sim_vio_4")

    def test_skip_must_not_fail(self):
        self.assertTrue(sim_vio_skip_must_not_fail())

    def test_pitch_rad(self):
        # iris base_link is Gazebo Z-up; +Y rotation positive is look-down.
        # FRD signed pitch −90 (look down) must command +π/2, not −π/2 (sky).
        self.assertEqual(pitch_deg_to_joint_rad(0), 0.0)
        self.assertAlmostEqual(pitch_deg_to_joint_rad(-90), math.pi / 2)

    def test_gz_argv_is_not_a_joint_command(self):
        rad = pitch_deg_to_joint_rad(-90)
        cmd = gz_pitch_cmd("iris_1", "vio_cam_pitch", rad)
        self.assertNotIn("joint", cmd)
        self.assertNotIn("--pos-t", cmd)
        self.assertNotIn("--pos-t0", cmd)

    def test_iris_and_joint_names(self):
        self.assertEqual(iris_model_name(2), "iris_2")
        self.assertEqual(vio_pitch_joint(), "vio_cam_pitch")

    def test_sim_vio_sh_has_gazebo_source_and_joint(self):
        text = (UTIL / "sim_vio.sh").read_text()
        self.assertIn("--source gazebo", text)
        pitch = _commands(_case_arm(text, "pitch"))
        self.assertNotIn("gz joint", pitch)
        self.assertNotIn("--pos-t", pitch)
        self.assertNotIn("--pos-t0", pitch)
        self.assertNotIn("gz model", pitch)

    def test_start_and_stop_exit_zero_pitch_forwards_gz(self):
        text = (UTIL / "sim_vio.sh").read_text()
        start = _case_arm(text, "start")
        stop = _case_arm(text, "stop")
        pitch = _commands(_case_arm(text, "pitch"))
        self.assertIn("exit 0", start)
        self.assertIn("exit 0", stop)
        self.assertIn("exit 0", pitch)
        self.assertNotIn("gz joint", pitch)
        self.assertNotIn("--pos-t", pitch)
        self.assertNotIn("gz model", pitch)
        self.assertNotIn("::vio_cam", pitch)

    def test_script_has_no_vision_position(self):
        text = (UTIL / "sim_vio.sh").read_text()
        self.assertNotIn("VISION_POSITION", text)

    def test_id_is_required(self):
        text = (UTIL / "sim_vio.sh").read_text()
        self.assertIn('id="${2:?}"', text)

    def test_stop_has_no_bare_drone_id_pkill(self):
        text = (UTIL / "sim_vio.sh").read_text()
        for line in _case_arm(text, "stop").splitlines():
            if "pkill" not in line:
                continue
            if "--drone-id" in line:
                self.assertIn(
                    "svo_pi",
                    line,
                    msg=f"bare --drone-id pkill would SIGTERM HA: {line}",
                )

    def test_stop_pkills_id_safe_socket_and_qualified_svo_pi(self):
        stop = _case_arm((UTIL / "sim_vio.sh").read_text(), "stop")
        self.assertIn("/tmp/svo_pi_${id}.sock", stop)
        self.assertIn("svo_pi.supervisor", stop)
        self.assertIn("svo_pi.feeder", stop)
        self.assertIn("/svo_pi/svo_pi", stop)
        self.assertIn("--drone-id=${id}([^0-9]|$)", stop)

    def test_tmux_targets_catswarm_session(self):
        text = (UTIL / "sim_vio.sh").read_text()
        self.assertIn("CATSWARM_TMUX_SESSION", text)
        self.assertIn("${session}:${window}", text)
        self.assertIn('tmux new-window -t "${session}"', text)

    def test_start_exports_host_library_path(self):
        start = _case_arm((UTIL / "sim_vio.sh").read_text(), "start")
        self.assertIn("LD_LIBRARY_PATH", start)
        self.assertIn("SCHURVINS_HOST_PREFIX", start)
        self.assertIn("sys/lib", start)

    def test_start_mavlink_is_dedicated_vio_instance_not_ha(self):
        start = _case_arm((UTIL / "sim_vio.sh").read_text(), "start")
        self.assertIn("14640 + id", start)
        self.assertNotIn("14540 + id - 1", start)
        self.assertNotIn("14540 + id", start)
