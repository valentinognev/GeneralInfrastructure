import tempfile
import unittest
from pathlib import Path

from companion_vio_spec import (
    default_calib_path,
    default_options_path,
    default_schurvins_root,
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

    def test_default_schurvins_root_prefers_nested_when_present(self):
        with tempfile.TemporaryDirectory() as td:
            cats = Path(td) / "CatSwarm"
            nested = cats / "SchurVINS"
            nested.mkdir(parents=True)
            self.assertEqual(default_schurvins_root(str(cats)), str(nested.resolve()))

    def test_default_schurvins_root_uses_sibling_when_nested_missing(self):
        with tempfile.TemporaryDirectory() as td:
            gi = Path(td) / "CatSwarm" / "general_infrastructure"
            gi.mkdir(parents=True)
            sibling = Path(td) / "CatSwarm" / "SchurVINS"
            sibling.mkdir()
            self.assertEqual(default_schurvins_root(str(gi)), str(sibling.resolve()))

    def test_start_script_prefers_nested_schurvins_then_sibling(self):
        text = (STARTUP / "start_companion_drone_tmux.sh").read_text()
        self.assertIn('[ -d "${CATSWARM_ROOT}/SchurVINS" ]', text)
        self.assertIn('$(cd "${CATSWARM_ROOT}/.." && pwd)/SchurVINS', text)
