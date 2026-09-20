#!/usr/bin/env bash
# Switch companion COMM fabric (WiFi star or serial RF); persist; restart ZMQ_to_comm only.
#
# Usage:
#   ~/RL/startup_scripts/switch_comm_WIFI_RF.sh [drone_id] --wifi|--rf [--gs-host=IP]
#   ~/RL/startup_scripts/switch_comm_WIFI_RF.sh 3 --wifi --gs-host=192.168.0.43
#   ~/RL/startup_scripts/switch_comm_WIFI_RF.sh 3 --rf
#
# Does not restart GPS/RTCM windows (COMM fabric is independent of RTK).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATSWARM_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UTIL_DIR="${SCRIPT_DIR}/util"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/util/companion_rtk_connection.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/util/companion_tmux.sh"

SESSION="${CATSWARM_TMUX_SESSION:-catswarm_sim}"
DRONE_ID=3
HW_WIN="hardware_adapter_${DRONE_ID}"
UART2="${COMPANION_UART2_GS_RADIO:-/dev/ttyAMA2}"
PYTHON="${PYTHON:-/home/pi/miniconda/envs/RL/bin/python}"
STATE_FILE="${COMPANION_COMM_STATE_FILE:-${HOME}/.config/companion-comm}"
_FABRIC=""
_GS_HOST_EXPLICIT=""

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [drone_id] --wifi|--rf [--gs-host=IP]
  $(basename "$0") -h|--help

Persist COMM fabric to ~/.config/companion-comm and restart
hardware_adapter_<id>.3 (ZMQ_to_comm). Does not restart GPS/RTCM.

Options:
  --wifi                  COMM via WiFi star (CONNECT :18811/:18812) and save
  --rf                    COMM via UART2 serial RF and save
  --gs-host=IP            GS IP for wifi COMM URLs

Saved COMM preference: ${STATE_FILE}

Examples:
  $(basename "$0") 3 --wifi --gs-host=192.168.0.43
  $(basename "$0") 3 --rf
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --wifi) _FABRIC=wifi; shift ;;
    --rf) _FABRIC=rf; shift ;;
    --gs-host=*) _GS_HOST_EXPLICIT="${1#*=}"; shift ;;
    --gs-host)
      [ $# -lt 2 ] && { echo "switch_comm_WIFI_RF.sh: --gs-host requires IP" >&2; exit 1; }
      _GS_HOST_EXPLICIT="$2"; shift 2 ;;
    [0-9]*) DRONE_ID="$1"; HW_WIN="hardware_adapter_${DRONE_ID}"; shift ;;
    -*)
      echo "$(basename "$0"): unknown option: $1" >&2
      echo "Run: $(basename "$0") --help" >&2
      exit 1
      ;;
    *)
      echo "$(basename "$0"): unexpected argument: $1" >&2
      echo "Run: $(basename "$0") --help" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${_FABRIC}" ]]; then
  echo "switch_comm_WIFI_RF.sh: --wifi or --rf is required" >&2
  echo "Run: $(basename "$0") --help" >&2
  exit 1
fi

_py="${PYTHON}"
if [[ ! -x "${_py}" ]]; then
  _py="$(command -v python3 || true)"
fi
if [[ -z "${_py}" ]]; then
  echo "switch_comm_WIFI_RF.sh: python not found" >&2
  exit 1
fi

_saved_host=""
if [[ -f "${STATE_FILE}" ]]; then
  _saved_host="$(
    PYTHONPATH="${UTIL_DIR}" "${_py}" -c \
      "from companion_comm import load_companion_comm; import sys; print(load_companion_comm(sys.argv[1]).get('COMPANION_COMM_GS_HOST',''))" \
      "${STATE_FILE}"
  )"
fi
GS_HOST="${_GS_HOST_EXPLICIT:-${_saved_host:-${COMPANION_BASE_HOST:-192.168.0.43}}}"

PYTHONPATH="${UTIL_DIR}" "${_py}" -c \
  "from companion_comm import save_companion_comm; import sys; save_companion_comm(sys.argv[1], sys.argv[2], sys.argv[3])" \
  "${STATE_FILE}" "${_FABRIC}" "${GS_HOST}"

export COMPANION_COMM_FABRIC="${_FABRIC}"
export COMPANION_COMM_GS_HOST="${GS_HOST}"

companion_rtk_resolve_mode
companion_rtk_apply_mode

if ! companion_tmux_bind_session "${SESSION}"; then
  echo "switch_comm_WIFI_RF.sh: tmux session ${SESSION} not found" >&2
  exit 1
fi

_EXTRA="$(
  PYTHONPATH="${UTIL_DIR}" "${_py}" -c \
    "from companion_comm import z2c_extra_args; import sys; print(' '.join(z2c_extra_args(sys.argv[1], sys.argv[2])))" \
    "${_FABRIC}" "${GS_HOST}"
)"

Z2C_BIN="${CATSWARM_ROOT}/hardware_adapter/bin/ZMQ_to_comm_c"
Z2C_PY="${CATSWARM_ROOT}/hardware_adapter/python/ZMQ_to_comm.py"
# Fleet C binary uses MultiInput-style ports (base + drone_id); Python path below is legacy.
FD_PORT=$((21700 + DRONE_ID))
COMM_PUB_PORT=$((7800 + DRONE_ID))
NEIGH_SUB_PORT=$((22700 + DRONE_ID))
MAV_FB_PORT=$((9900 + DRONE_ID))
if [[ -x "${Z2C_BIN}" ]]; then
  Z2C_CMD="${Z2C_BIN}"
  Z2C_CMD+=" --zmq-flight-data-port=${FD_PORT} --zmq-comm-pub-port=${COMM_PUB_PORT}"
  Z2C_CMD+=" --drone-id=${DRONE_ID} --zmq-mavlink-fallback-port=${MAV_FB_PORT}"
  Z2C_CMD+=" --zmq-comm-neighbour-sub-port=${NEIGH_SUB_PORT}"
  Z2C_CMD+=" --zmq-sys-manager-out-port=${FD_PORT}"
  Z2C_CMD+=" --serialcomm=${UART2} --zmq-gs-forward-port=7799"
  if [[ "${COMPANION_USE_RF_RTK_BRIDGE}" -eq 1 ]]; then
    Z2C_CMD+=" --rtk-zmq-bind=${COMPANION_RTK_ZMQ_BIND}"
  fi
  if [[ "${_FABRIC}" != "wifi" ]]; then
    Z2C_CMD+=" --serial-comm-tx"
  fi
  if [[ -n "${_EXTRA}" ]]; then
    Z2C_CMD+=" ${_EXTRA}"
  fi
  _Z2C_LAUNCH_CD="${CATSWARM_ROOT}/hardware_adapter"
else
  Z2C_CMD="${PYTHON} ${Z2C_PY}"
  Z2C_CMD+=" --zmq-flight-data-port=${FD_PORT} --zmq-comm-pub-port=${COMM_PUB_PORT}"
  Z2C_CMD+=" --drone-id=${DRONE_ID} --zmq-mavlink-fallback-port=${MAV_FB_PORT}"
  Z2C_CMD+=" --zmq-comm-neighbour-sub-port=${NEIGH_SUB_PORT}"
  Z2C_CMD+=" --serialcomm=${UART2}"
  if [[ "${_FABRIC}" != "wifi" ]]; then
    Z2C_CMD+=" --serial-comm-tx"
  fi
  if [[ "${COMPANION_USE_RF_RTK_BRIDGE}" -eq 1 ]]; then
    Z2C_CMD+=" --rtk-zmq-bind=${COMPANION_RTK_ZMQ_BIND}"
  fi
  if [[ -n "${_EXTRA}" ]]; then
    Z2C_CMD+=" ${_EXTRA}"
  fi
  _Z2C_LAUNCH_CD="${CATSWARM_ROOT}/hardware_adapter/python"
fi

_send() {
  local target="$1"
  local inner_cmd="$2"
  tmux send-keys -t "${target}" C-c
  sleep 1.5
  local launch="cd ${_Z2C_LAUNCH_CD} && export PYTHONPATH=${CATSWARM_ROOT}/system_manager/system_managerPY:\$PYTHONPATH && ${inner_cmd}"
  if [[ -n "${COMPANION_RUN_IN_RL:-}" ]] && [[ -x "${COMPANION_RUN_IN_RL}" ]]; then
    launch="${COMPANION_RUN_IN_RL} $(printf '%q' "${launch}")"
  fi
  tmux send-keys -t "${target}" "${launch}" C-m
}

echo "switch_comm_WIFI_RF.sh: COMM=${_FABRIC} gs=${GS_HOST}" >&2
echo "switch_comm_WIFI_RF.sh: restarting ${SESSION}:${HW_WIN}.3 (ZMQ_to_comm)…" >&2
_send "${SESSION}:${HW_WIN}.3" "${Z2C_CMD}"

sleep 2
echo "switch_comm_WIFI_RF.sh: done. Attach: tmux attach -t ${SESSION}" >&2
