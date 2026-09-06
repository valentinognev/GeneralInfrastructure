import unittest
from companion_vio_spec import vio_window_name, vio_skip_must_not_fail_companion


class TestCompanionVio(unittest.TestCase):
    def test_window_name(self):
        self.assertEqual(vio_window_name(1), "vio_1")
        self.assertEqual(vio_window_name(4), "vio_4")

    def test_skip_policy(self):
        self.assertTrue(vio_skip_must_not_fail_companion())
