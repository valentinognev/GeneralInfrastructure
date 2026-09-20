# Bind this shell's tmux client to the companion session's server.
# systemd companion-drone.service is Type=oneshot User=pi with no XDG_RUNTIME_DIR,
# so tmux 3.2+ stores the socket under /tmp/tmux-<uid>/. SSH PAM sets
# XDG_RUNTIME_DIR=/run/user/<uid> and talks to a different empty server.
companion_tmux_bind_session() {
  local session="${1:-${CATSWARM_TMUX_SESSION:-catswarm_sim}}"
  if tmux has-session -t "${session}" 2>/dev/null; then
    return 0
  fi
  if TMUX_TMPDIR=/tmp XDG_RUNTIME_DIR= tmux has-session -t "${session}" 2>/dev/null; then
    export TMUX_TMPDIR=/tmp
    unset XDG_RUNTIME_DIR
    return 0
  fi
  local runtime="/run/user/$(id -u)"
  if [[ -d "${runtime}" ]] && \
      XDG_RUNTIME_DIR="${runtime}" TMUX_TMPDIR= tmux has-session -t "${session}" 2>/dev/null; then
    export XDG_RUNTIME_DIR="${runtime}"
    unset TMUX_TMPDIR
    return 0
  fi
  return 1
}

# Capture every pane's stdout to rotating files under ~/RL/logs/tmux (survives reboot).
companion_tmux_pipe_session() {
  local session="$1"
  local log_dir="${2:-${HOME}/RL/logs/tmux}"
  mkdir -p "$log_dir"
  local stamp; stamp="$(date -u +%Y%m%d_%H%M%SZ)"
  companion_tmux_bind_session "$session" || true
  local target
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    local safe; safe="$(printf '%s' "$target" | tr ':. ' '___')"
    tmux pipe-pane -o -t "$target" "cat >> \"${log_dir}/${stamp}_${safe}.log\""
  done < <(tmux list-panes -s -t "$session" -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)
}
