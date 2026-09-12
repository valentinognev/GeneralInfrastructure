from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITL = ROOT / "multidrone" / "sitl_multiple_run.sh"
RUN = ROOT / "runSimNoeticMulti.sh"


def test_sitl_appends_catswarm_host_after_setup():
    text = SITL.read_text()
    i_src = text.index("setup_gazebo.bash")
    i_host = text.index("models/catswarm_host")
    assert i_src < i_host
    assert "GAZEBO_MODEL_PATH" in text


def test_runsim_help_and_world_flag():
    import subprocess
    out = subprocess.check_output(["bash", str(RUN), "--help"], text=True)
    assert "--world" in out
    assert "--vio-cam" in out
    assert "--vio-pitch" in out
    assert "CATSWARM_VIO_PITCH" in RUN.read_text()


def test_runsim_missing_world_exits_before_docker(tmp_path):
    import subprocess
    proc = subprocess.run(
        ["bash", str(RUN), "--world", "definitely_missing_world_xyz", "--num", "1"],
        cwd=str(ROOT), capture_output=True, text=True, timeout=15,
    )
    assert proc.returncode != 0
    assert "generate_real_area.py" in (proc.stdout + proc.stderr)
