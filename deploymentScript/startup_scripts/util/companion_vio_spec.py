def vio_window_name(drone_id: int) -> str:
    return f"vio_{int(drone_id)}"


def vio_skip_must_not_fail_companion() -> bool:
    return True
