#!/usr/bin/env bash
# Host Sim VIO (SchurVINS svo_pi --source gazebo) tmux window.
# Usage:
#   sim_vio.sh start <id> <python> <schurvins> <calib> <options>
#   sim_vio.sh stop <id>
#   sim_vio.sh pitch <id> <deg>
#
# start always returns 0 (skip/park never fails the swarm).
# pitch returns gz's exit code (nonzero if the model is missing).

set -u

sim_vio_window_name() { echo "sim_vio_${1}"; }

cmd="${1:-}"
id="${2:?}"
session="${CATSWARM_TMUX_SESSION:-catswarm_sim}"

case "$cmd" in
  start)
    python="${3:?}"
    schurvins="${4:?}"
    calib="${5:?}"
    options="${6:?}"
    window="$(sim_vio_window_name "${id}")"
    py_root="${schurvins}/svo_pi/python"
    sock="/tmp/svo_pi_${id}.sock"
    tmux has-session -t "${session}" 2>/dev/null || tmux new-session -d -s "${session}"
    tmux kill-window -t "${session}:${window}" 2>/dev/null || true
    tmux new-window -t "${session}" -n "${window}" \
      "export PYTHONPATH='${py_root}'; ${python} -m svo_pi.supervisor --drone-id=${id} --svo-pi='${schurvins}/svo_pi/svo_pi' --calib='${calib}' --options='${options}' --source gazebo --mavlink=udp:127.0.0.1:$((14540 + id - 1)); echo; echo '[sim_vio window parked]'; exec sleep infinity"
    exit 0
    ;;
  stop)
    window="$(sim_vio_window_name "${id}")"
    tmux kill-window -t "${session}:${window}" 2>/dev/null || true
    pkill -TERM -f "/tmp/svo_pi_${id}.sock" 2>/dev/null || true
    pkill -TERM -f "svo_pi.supervisor.*--drone-id=${id}([^0-9]|$)" 2>/dev/null || true
    pkill -TERM -f "svo_pi.feeder.*--drone-id=${id}([^0-9]|$)" 2>/dev/null || true
    pkill -TERM -f "/svo_pi/svo_pi.*--drone-id=${id}([^0-9]|$)" 2>/dev/null || true
    exit 0
    ;;
  pitch)
    deg="${3:?}"
    rad="$(python3 -c "import math; print(math.radians(float('${deg}')))")"
    docker exec px4-noetic-sim-ros gz joint -m "iris_${id}" -j vio_cam_pitch --pos-t0 "${rad}"
    exit $?
    ;;
  *)
    echo "usage: $0 start <id> <python> <schurvins> <calib> <options> | stop <id> | pitch <id> <deg>" >&2
    exit 2
    ;;
esac
