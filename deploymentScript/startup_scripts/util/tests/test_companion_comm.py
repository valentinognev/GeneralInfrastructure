from pathlib import Path
from companion_comm import load_companion_comm, save_companion_comm, z2c_extra_args

UTIL = Path(__file__).resolve().parents[1]
STARTUP = UTIL.parent
SWITCH = STARTUP / "switch_comm_WIFI_RF.sh"
SWITCH_RTK = STARTUP / "switch_rtk_WIFI_RF.sh"
BOOT = STARTUP / "start_companion_drone_tmux.sh"


def test_save_load_roundtrip(tmp_path: Path):
    p = tmp_path / "companion-comm"
    save_companion_comm(p, "wifi", "192.168.0.43")
    d = load_companion_comm(p)
    assert d["COMPANION_COMM_FABRIC"] == "wifi"
    assert d["COMPANION_COMM_GS_HOST"] == "192.168.0.43"


def test_z2c_extra_args_wifi():
    args = z2c_extra_args("wifi", "192.168.0.43")
    assert "--wifi-comm-uplink=tcp://192.168.0.43:18811" in args
    assert "--wifi-comm-downlink=tcp://192.168.0.43:18812" in args
    assert z2c_extra_args("rf", "192.168.0.43") == []


def test_switch_comm_tmux_bind_and_pane_only():
    text = SWITCH.read_text()
    assert "companion_tmux.sh" in text
    assert "companion_tmux_bind_session" in text
    assert "${SESSION}:${HW_WIN}.3" in text
    assert "companion_gps_start_in_tmux" not in text
    assert "companion_rtcm_mavlink_start_in_tmux" not in text
    assert "z2c_extra_args" in text
    assert "--gs-host=" in text


def test_boot_exports_fabric_and_wifi_comm_host():
    text = BOOT.read_text()
    assert "companion-comm" in text
    assert "COMPANION_COMM_FABRIC" in text
    assert "COMPANION_COMM_GS_HOST" in text
    assert "--wifi-comm-host=" in text


def test_switch_rtk_honors_saved_wifi_comm_on_z2c_relaunch():
    """Apply RTK must not drop WiFi COMM: same Z2C table as switch_comm / hardware_adapter_multi."""
    text = SWITCH_RTK.read_text()
    assert "load_companion_comm" in text
    assert "z2c_extra_args" in text
    assert '!= "wifi"' in text
    assert "save_companion_comm" not in text
    assert "--rtk-zmq-bind=${COMPANION_RTK_ZMQ_BIND} --serial-comm-tx" not in text
    # Both C and Python launches append extra argv and omit serial TX when wifi.
    assert text.count('Z2C_CMD+=" ${_EXTRA}"') == 2
    assert text.count('if [[ "${_FABRIC}" != "wifi" ]]; then') == 2
