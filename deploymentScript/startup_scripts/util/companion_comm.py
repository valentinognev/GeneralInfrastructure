"""Companion COMM fabric persist + ZMQ_to_comm extra argv (Task 7 tokens)."""

from __future__ import annotations

from pathlib import Path

_UPLINK_PORT = 18811
_DOWNLINK_PORT = 18812
_DEFAULT_FABRIC = "rf"


def load_companion_comm(path: str | Path) -> dict:
    data = {
        "COMPANION_COMM_FABRIC": _DEFAULT_FABRIC,
        "COMPANION_COMM_GS_HOST": "",
    }
    p = Path(path)
    if not p.is_file():
        return data
    for raw in p.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip().strip("'\"")
        if key in ("COMPANION_COMM_FABRIC", "COMPANION_COMM_GS_HOST"):
            data[key] = val
    fabric = data["COMPANION_COMM_FABRIC"].strip().lower()
    data["COMPANION_COMM_FABRIC"] = fabric if fabric in ("wifi", "rf") else _DEFAULT_FABRIC
    return data


def save_companion_comm(path: str | Path, fabric: str, gs_host: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    fabric_n = (fabric or _DEFAULT_FABRIC).strip().lower()
    if fabric_n not in ("wifi", "rf"):
        fabric_n = _DEFAULT_FABRIC
    host = (gs_host or "").strip()
    p.write_text(
        "# Last companion COMM fabric (edit or use switch_comm_WIFI_RF.sh --wifi|--rf [--gs-host=])\n"
        f"COMPANION_COMM_FABRIC={fabric_n}\n"
        f"COMPANION_COMM_GS_HOST={host}\n"
    )
    try:
        p.chmod(0o644)
    except OSError:
        pass


def z2c_extra_args(fabric: str, gs_host: str) -> list[str]:
    if (fabric or "").strip().lower() != "wifi":
        return []
    host = (gs_host or "").strip()
    return [
        f"--wifi-comm-uplink=tcp://{host}:{_UPLINK_PORT}",
        f"--wifi-comm-downlink=tcp://{host}:{_DOWNLINK_PORT}",
    ]
