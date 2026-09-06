import unittest
from pathlib import Path

from companion_vio_spec import (
    default_calib_path,
    default_options_path,
    vio_skip_must_not_fail_companion,
    vio_window_name,
)

UTIL = Path(__file__).resolve().parents[1]
STARTUP = UTIL.parent


class TestCompanionVio(unittest.TestCase):
    def test_window_name(self):
        self.assertEqual(vio_window_name(1), "vio_1")
        self.assertEqual(vio_window_name(4), "vio_4")

    def test_skip_policy(self):
        self.assertTrue(vio_skip_must_not_fail_companion())

    def test_default_yaml_paths(self):
        root = "/opt/SchurVINS"
        self.assertEqual(
            default_calib_path(root),
            "/opt/SchurVINS/svo_ros/param/calib/imx500_320.yaml",
        )
        self.assertEqual(
            default_options_path(root),
            "/opt/SchurVINS/svo_ros/param/vio_mono.yaml",
        )

    def test_tmux_hook_passes_imx500_calib_and_options(self):
        text = (UTIL / "companion_vio.sh").read_text()
        self.assertIn("--calib=${schurvins}/svo_ros/param/calib/imx500_320.yaml", text)
        self.assertIn("--options=${schurvins}/svo_ros/param/vio_mono.yaml", text)

    def test_kill_companion_pkills_feeder(self):
        text = (STARTUP / "start_companion_drone_tmux.sh").read_text()
        self.assertIn('pkill -TERM -f "svo_pi.feeder"', text)
