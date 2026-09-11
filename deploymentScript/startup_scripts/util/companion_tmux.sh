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
