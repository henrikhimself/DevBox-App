#!/usr/bin/env bash
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/ssh.sh,
# Docker/ssh.sh), which has already sourced its shared.sh (adapter + libraries).

dv::require_jq

dv::usage() {
  cat <<'EOF'
Usage: [options]

Options:
  -v profile-name  Optional profile name selecting which devbox profile to connect to; auto-detected if omitted and exactly one is running
  -s session-name  Optional tmux session name; land in tmux session
                   devbox-<profile>:<session-name> instead of the default
                   devbox-<profile> session

Opens an SSH session against the running devbox container for the given
profile. The profile must already be running (via run.sh, with or without
-k). The connection lands in a per-profile tmux session (devbox-<profile>):
it is created with a login shell in the workspace directory if it does not
exist, or attached if it already does — so reconnecting resumes exactly where
you left off. Detach with Ctrl-b d (the session keeps running in the
container) and run this script again to re-attach. Sessions end when the
container is stopped or removed. Use -s for a named second session (one
terminal per session); inside tmux, Ctrl-b s switches between the profile's
sessions.
EOF
}

while getopts ':v:s:' opt; do
  case "${opt}" in
    v)
      PROFILE_NAME="${OPTARG}"
      ;;
    s)
      SESSION_NAME="${OPTARG}"
      ;;
    :)
      dv::opt_error ':' "${OPTARG}" dv::usage
      ;;
    \?)
      dv::opt_error '?' "${OPTARG}" dv::usage
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ $# -ne 0 ]]; then
  dv::usage
  exit 1
fi

if [[ -n "${SESSION_NAME:-}" ]]; then
  dv::validate_devbox_name "${SESSION_NAME}" 'session-name'
fi

dv::ensure_container_backend_running

dv::resolve_running_devbox "${PROFILE_NAME:-}"
dv::prepare_ssh_alias

# One tmux session per profile (plus optional -s named sessions). The session
# lives inside the container: it dies with the container, and the tmux server
# keeps it running across SSH disconnects.
SESSION="devbox-${PROFILE_NAME}"
if [[ -n "${SESSION_NAME:-}" ]]; then
  SESSION="${SESSION}:${SESSION_NAME}"
fi

printf '%s\n' "🚀 Connecting via SSH to profile '${PROFILE_NAME}' (${CONTAINER_NAME}, port ${PORT}, tmux session '${SESSION}')..."
exec ssh -t "${ALIAS}" "tmux -u new-session -A -s '${SESSION}' -c '${TARGET_PATH}' bash -l"
