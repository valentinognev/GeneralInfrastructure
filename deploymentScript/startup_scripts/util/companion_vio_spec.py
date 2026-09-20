import os


def vio_window_name(drone_id: int) -> str:
    return f"vio_{int(drone_id)}"


def vio_skip_must_not_fail_companion() -> bool:
    return True


def default_calib_path(schurvins_root: str) -> str:
    return f"{schurvins_root.rstrip('/')}/svo_ros/param/calib/imx500_320.yaml"


def default_options_path(schurvins_root: str) -> str:
    return f"{schurvins_root.rstrip('/')}/svo_ros/param/vio_mono.yaml"


def default_schurvins_root(catswarm_root: str, *, is_dir=os.path.isdir) -> str:
    root = os.path.abspath(catswarm_root)
    nested = os.path.join(root, "SchurVINS")
    if is_dir(nested):
        return nested
    return os.path.join(os.path.dirname(root), "SchurVINS")
