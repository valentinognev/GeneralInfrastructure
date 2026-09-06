#!/usr/bin/env bash
# Companion VIO (SchurVINS svo_pi) tmux window.
#
# Source this file, then call:
#   companion_vio_start_in_tmux SESSION DRONE_ID PYTHON SCHURVINS_ROOT
#
# Camera missing or svo_pi not executable → supervisor prints skip and returns 0.
# This helper always returns 0 so companion start never exit 1 on VIO skip/failure.
# Window stays parked with sleep infinity.

companion_vio_window_name() { echo "vio_${1}"; }

companion_vio_start_in_tmux() {
  local session="$1" drone_id="$2" python="$3" schurvins="$4"
  local window; window="$(companion_vio_window_name "${drone_id}")"
  local py_root="${schurvins}/svo_pi/python"
  tmux kill-window -t "${session}:${window}" 2>/dev/null || true
  tmux new-window -t "${session}" -n "${window}" \
    "export PYTHONPATH='${py_root}'; ${python} -m svo_pi.supervisor --drone-id=${drone_id} --svo-pi='${schurvins}/svo_pi/svo_pi' --calib=${schurvins}/svo_ros/param/calib/imx500_320.yaml --options=${schurvins}/svo_ros/param/vio_mono.yaml; echo; echo '[vio window parked]'; exec sleep infinity"
  return 0
}
