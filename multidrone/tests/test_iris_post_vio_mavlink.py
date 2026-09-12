from pathlib import Path

POST = Path(__file__).resolve().parents[1] / "airframes" / "10015_gazebo-classic_iris.post"


def test_iris_post_starts_dedicated_vio_mavlink():
    text = POST.read_text()
    compact = text.replace(" ", "")
    assert "udp_vio_port_remote=$((14640+px4_instance))" in compact
    assert "udp_vio_port_local=$((14680+px4_instance))" in compact
    assert "HIGHRES_IMU" in text
    assert "GLOBAL_POSITION_INT" in text
    assert "LOCAL_POSITION_NED" in text
    assert "mavlink start" in text
    assert "-o$udp_vio_port_remote" in compact
