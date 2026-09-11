import math


def sim_vio_window_name(drone_id: int) -> str:
    return f"sim_vio_{int(drone_id)}"


def sim_vio_skip_must_not_fail() -> bool:
    return True


def pitch_deg_to_joint_rad(pitch_deg: float) -> float:
    return math.radians(float(pitch_deg))


def gz_pitch_cmd(model: str, joint: str, rad: float) -> list[str]:
    return ["gz", "joint", "-m", model, "-j", joint, "--pos-t0", str(rad)]


def iris_model_name(drone_id: int) -> str:
    return f"iris_{int(drone_id)}"


def vio_pitch_joint() -> str:
    return "vio_cam_pitch"
