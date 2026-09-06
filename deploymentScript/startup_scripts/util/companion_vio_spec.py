def vio_window_name(drone_id: int) -> str:
    return f"vio_{int(drone_id)}"


def vio_skip_must_not_fail_companion() -> bool:
    return True


def default_calib_path(schurvins_root: str) -> str:
    return f"{schurvins_root.rstrip('/')}/svo_ros/param/calib/imx500_320.yaml"


def default_options_path(schurvins_root: str) -> str:
    return f"{schurvins_root.rstrip('/')}/svo_ros/param/vio_mono.yaml"
