#!/usr/bin/env bash
# shellcheck disable=SC2310 # Forward-status helpers are predicates with expected non-zero results.
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/forward.sh,
# Docker/forward.sh), which has already sourced its shared.sh (adapter + libraries).

dv::require_jq

dv::usage() {
  cat <<'EOF'
Usage: [options]

Options:
  -v profile-name  Optional profile name selecting which devbox profile to forward for; auto-detected if omitted (from running profiles when starting a forward, or from existing forwards on the given port when closing one with -D)
  -p host-port[:container-port]  Host port to forward from; if container-port is omitted, the same port number is used inside the devbox. Required to start a forward; optional with -D (see below)
  -D               Close forward(s) instead of starting one. With -p, closes that specific forward. Without -p, closes ALL active forwards (scoped to -v's profile if given, otherwise every profile) after a confirmation prompt
  -y               Skip the confirmation prompt for -D's bulk-close (no -p) and close immediately
  -l               List active forwards (scoped to -v's profile if given, otherwise every profile) instead of starting or closing one. Mutually exclusive with -p/-D

Forwards a TCP port from a service listening on localhost inside a running
devbox container to a port on this host, via an SSH tunnel over the
devbox-<profile> SSH alias (see code.sh/ssh.sh). The profile must already be
running (via run.sh, with or without -k) to start a forward.

Never run this script with sudo — that breaks
container-runtime queries for your normal user. For a privileged host port
(<1024), run it normally: it prompts for sudo itself, only for the specific
bind step that needs it.
EOF
}

PROFILE_NAME=''
PORT_SPEC=''
CLOSE=0
ASSUME_YES=0
LIST=0

while getopts ':v:p:Dyl' opt; do
  case "${opt}" in
    v)
      PROFILE_NAME="${OPTARG}"
      ;;
    p)
      PORT_SPEC="${OPTARG}"
      ;;
    D)
      CLOSE=1
      ;;
    y)
      ASSUME_YES=1
      ;;
    l)
      LIST=1
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

if [[ "${LIST}" -eq 1 ]]; then
  if [[ -n "${PORT_SPEC}" || "${CLOSE}" -eq 1 ]]; then
    dv::usage
    exit 1
  fi

  ALL_FORWARDS="$(dv::list_all_forwards)"
  if [[ -n "${PROFILE_NAME}" ]]; then
    dv::validate_profile_name "${PROFILE_NAME}"
    ALL_FORWARDS="$(printf '%s\n' "${ALL_FORWARDS}" | awk -F: -v p="${PROFILE_NAME}" '$1 == p')"
  fi

  if [[ -z "${ALL_FORWARDS}" ]]; then
    if [[ -n "${PROFILE_NAME}" ]]; then
      printf '%s\n' "No active port forwards for profile '${PROFILE_NAME}'."
    else
      printf '%s\n' 'No active port forwards.'
    fi
    exit 0
  fi

  printf '%s\t%s\t%s\n' 'PROFILE' 'HOST_PORT' 'CONTAINER_PORT'
  while IFS=: read -r profile host container; do
    [[ -z "${profile}" ]] && continue
    printf '%s\t%s\t%s\n' "${profile}" "${host}" "${container}"
  done <<< "${ALL_FORWARDS}"
  exit 0
fi

if [[ "${CLOSE}" -eq 1 && -z "${PORT_SPEC}" ]]; then
  # Bulk-close: -D with no -p closes all active forwards (scoped to -v's
  # profile if given, else every profile), with a confirmation unless -y.
  if [[ -n "${PROFILE_NAME}" ]]; then
    dv::validate_profile_name "${PROFILE_NAME}"
    FORWARDS="$(dv::list_forwards_for_profile "${PROFILE_NAME}")"
    if [[ -z "${FORWARDS}" ]]; then
      printf '%s\n' "❌ No active forwards found for profile '${PROFILE_NAME}'." >&2
      exit 1
    fi
    FORWARD_COUNT="$(printf '%s\n' "${FORWARDS}" | tr ',' '\n' | grep -c . || true)"
    PROMPT="Close ${FORWARD_COUNT} active port forward(s) for profile '${PROFILE_NAME}'?"
  else
    ALL_FORWARDS="$(dv::list_all_forwards)"
    FORWARD_COUNT="$(printf '%s\n' "${ALL_FORWARDS}" | grep -c . || true)"
    if [[ "${FORWARD_COUNT}" -eq 0 ]]; then
      printf '%s\n' '❌ No active forwards found.' >&2
      exit 1
    fi
    PROMPT="Close ${FORWARD_COUNT} active port forward(s) across all profiles?"
  fi

  dv::confirm "${PROMPT}" "${ASSUME_YES}" || exit 1

  if [[ -n "${PROFILE_NAME}" ]]; then
    dv::close_all_forwards_for_profile "${PROFILE_NAME}"
  else
    dv::close_all_forwards
  fi
  exit 0
fi

if [[ -z "${PORT_SPEC}" ]]; then
  printf '%s\n' '❌ -p host-port[:container-port] is required.' >&2
  dv::usage
  exit 1
fi

if [[ "${PORT_SPEC}" == *:* ]]; then
  HOST_PORT="${PORT_SPEC%%:*}"
  CONTAINER_PORT="${PORT_SPEC#*:}"
else
  HOST_PORT="${PORT_SPEC}"
  CONTAINER_PORT="${PORT_SPEC}"
fi

for p in "${HOST_PORT}" "${CONTAINER_PORT}"; do
  if ! [[ "${p}" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
    printf '%s\n' "❌ Ports must be integers between 1 and 65535, got: '${p}'" >&2
    exit 1
  fi
done

if [[ "${CLOSE}" -eq 1 ]]; then
  # Independent of container state: a forward's lifecycle is its control
  # socket, so closing works even after the container stopped or crashed.
  if [[ -n "${PROFILE_NAME}" ]]; then
    dv::validate_profile_name "${PROFILE_NAME}"
  else
    MATCHES="$(dv::find_forward_profiles_by_port "${HOST_PORT}" "${CONTAINER_PORT}")"
    MATCH_COUNT="$(printf '%s\n' "${MATCHES}" | grep -c . || true)"
    if [[ "${MATCH_COUNT}" -eq 0 ]]; then
      printf '%s\n' "❌ No active forward found on ${HOST_PORT}:${CONTAINER_PORT} for any profile." >&2
      exit 1
    elif [[ "${MATCH_COUNT}" -gt 1 ]]; then
      printf '%s\n' "❌ Multiple profiles have an active forward on ${HOST_PORT}:${CONTAINER_PORT}. Use -v to pick one." >&2
      exit 1
    fi
    PROFILE_NAME="${MATCHES}"
  fi

  SOCKET_PATH="$(dv::forward_socket_path "${PROFILE_NAME}" "${HOST_PORT}" "${CONTAINER_PORT}")"

  if ! dv::forward_is_active "${SOCKET_PATH}"; then
    printf '%s\n' "❌ No active forward found for profile '${PROFILE_NAME}' on ${HOST_PORT}:${CONTAINER_PORT}." >&2
    rm -f "${SOCKET_PATH}"
    exit 1
  fi

  dv::close_forward_socket "${SOCKET_PATH}" "${PROFILE_NAME}" "${HOST_PORT}" "${CONTAINER_PORT}"
  exit 0
fi

if [[ "${EUID}" -eq 0 ]]; then
  printf '%s\n' "❌ Don't run forward.sh with sudo — running the whole" >&2
  printf '%s\n' "script as root breaks container-runtime queries for your normal user (e.g." >&2
  printf '%s\n' "${DEVBOX_RUNTIME_SESSION_HINT})." >&2
  printf '%s\n' "Run it as your normal user instead; if the host port is privileged (<1024)," >&2
  printf '%s\n' "forward.sh prompts for sudo itself, only for the specific bind step that needs it." >&2
  exit 1
fi

dv::ensure_container_backend_running

dv::resolve_running_devbox "${PROFILE_NAME:-}"
dv::prepare_ssh_alias

SOCKET_DIR="$(dv::forward_socket_dir)"
mkdir -p "${SOCKET_DIR}"
chmod 700 "${SOCKET_DIR}"
SOCKET_PATH="$(dv::forward_socket_path "${PROFILE_NAME}" "${HOST_PORT}" "${CONTAINER_PORT}")"

if dv::forward_is_active "${SOCKET_PATH}"; then
  printf '%s\n' "⚠️  A forward for ${HOST_PORT}:${CONTAINER_PORT} is already active for profile '${PROFILE_NAME}'." >&2
  exit 0
fi
rm -f "${SOCKET_PATH}"

# Connection params are passed explicitly, not via the devbox_config alias:
# a privileged port runs this under sudo, where root's ~/.ssh/config (not the
# user's) would otherwise be consulted.
SSH_FORWARD_CMD=(
  ssh -M -S "${SOCKET_PATH}" -fNT
  -o ExitOnForwardFailure=yes
  -o ControlPersist=no
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

# Resolve this user's SSH identity now, from this $HOME, before any sudo
# escalation — otherwise a privileged-port forward authenticates as root and
# fails with "Permission denied (publickey)". IdentityAgent points at the
# user's agent socket; the explicit IdentityFile list re-adds ssh's default
# key search, which naming any IdentityFile would otherwise disable (making
# sudo search root's home).
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  SSH_FORWARD_CMD+=(-o "IdentityAgent=${SSH_AUTH_SOCK}")
fi
for key_name in id_ed25519 id_ecdsa id_ecdsa_sk id_ed25519_sk id_rsa id_dsa; do
  if [[ -r "${HOME}/.ssh/${key_name}" ]]; then
    SSH_FORWARD_CMD+=(-o "IdentityFile=${HOME}/.ssh/${key_name}")
  fi
done

SSH_FORWARD_CMD+=(
  -p "${PORT}"
  -L "${HOST_PORT}:localhost:${CONTAINER_PORT}"
  bob@localhost
)

printf '%s\n' "🚀 Forwarding host port ${HOST_PORT} -> devbox '${PROFILE_NAME}' port ${CONTAINER_PORT}..."

if (( HOST_PORT < 1024 )); then
  printf '%s\n' "🔐 Host port ${HOST_PORT} is privileged (<1024); sudo is needed to bind it."
  if ! sudo "${SSH_FORWARD_CMD[@]}"; then
    printf '%s\n' "❌ Failed to establish the forward. Check that host port ${HOST_PORT} isn't already in use." >&2
    rm -f "${SOCKET_PATH}"
    exit 1
  fi
  # The socket file stays root-owned deliberately: ControlMaster checks the
  # connecting process's real UID against the master's, not the file's owner,
  # so dv::close_forward_socket's sudo escalation (not chown) is what lets us
  # manage it later.
elif ! "${SSH_FORWARD_CMD[@]}"; then
  printf '%s\n' "❌ Failed to establish the forward. Check that host port ${HOST_PORT} isn't already in use." >&2
  rm -f "${SOCKET_PATH}"
  exit 1
fi
