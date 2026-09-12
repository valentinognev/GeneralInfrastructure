import math


def sim_vio_window_name(drone_id: int) -> str:
    return f"sim_vio_{int(drone_id)}"


def sim_vio_skip_must_not_fail() -> bool:
    return True


def pitch_deg_to_joint_rad(pitch_deg: float) -> float:
    """FRD signed pitch (0=forward, −90=down) → Gazebo Z-up joint radians.

    iris ``base_link`` is Z-up; +Y rotation positive looks down, so FRD −90°
    is ``+π/2`` (not ``−π/2``, which points the camera at the sky).
    """
    return math.radians(-float(pitch_deg))


def gz_pitch_cmd(model: str, joint: str, rad: float) -> list[str]:
    # Never ``gz joint --pos-t``: unlimited-effort PID yanks iris to the origin.
    return []


def iris_model_name(drone_id: int) -> str:
    return f"iris_{int(drone_id)}"


def vio_pitch_joint() -> str:
    return "vio_cam_pitch"
