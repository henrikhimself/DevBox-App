#!/usr/bin/env bash
# shellcheck disable=SC2310 # Port-conflict lookup intentionally returns non-zero when no conflict exists.
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/run.sh,
# Docker/run.sh), which has already sourced its shared.sh (adapter + libraries).

dv::usage() {
  cat <<'EOF'
Usage: [options] [workspace-path]

Options:
  -m memory-gb     Optional memory in GB, default: 2
  -c cpu-cores     Optional CPU cores for --cpus, default: one less than total cores
  -p host-port     Optional host port mapped to container SSH; if omitted, an
                    available port is auto-selected from the pool 55000-59000
  -v profile-name  Optional profile name for an independent devbox profile, default: home
  -t target-path   Optional exact target path inside the container where the
                   workspace is bind-mounted. By default (no -t) the project
                   is bind-mounted at /workspace/<project-name>, named after
                   the workspace directory's basename (/workspace/root if the
                   path is /).
  -k               Optional flag to keep the container after stopping it, so
                    container-level changes persist for later. Rerunning
                    with -k for the same profile resumes the kept
                    container as-is, ignoring workspace-path and -m/-c/-p/-t
                    (workspace-path may be omitted entirely in that case).

Argument:
  workspace-path   Bind-mount source for workspace. Required, except when
                   resuming an existing kept container with -k (in which
                   case it is ignored if given, and may be omitted).
EOF
}

dv::resolve_workspace_path() {
  local path="${1}"
  (cd "${path}" && pwd -P)
}

dv::require_jq

MEMORY_GB='2'
CPU_CORES="$(dv::cpu_cores_default)"
HOST_PORT=''
PROFILE_NAME='home'
TARGET_PATH='/workspace'
TARGET_SET=0
KEEP=0
DEVBOX_IMAGE="${DEVBOX_IMAGE:-${DEVBOX_DEFAULT_IMAGE}}"
PORT_POOL_START="${DEVBOX_PORT_POOL_START:-55000}"
PORT_POOL_END="${DEVBOX_PORT_POOL_END:-59000}"

while getopts ':m:c:p:v:t:k' opt; do
  case "${opt}" in
    m)
      MEMORY_GB="${OPTARG}"
      ;;
    c)
      CPU_CORES="${OPTARG}"
      ;;
    p)
      HOST_PORT="${OPTARG}"
      ;;
    v)
      PROFILE_NAME="${OPTARG}"
      ;;
    t)
      TARGET_PATH="${OPTARG}"
      TARGET_SET=1
      ;;
    k)
      KEEP=1
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

if [[ "${KEEP}" -eq 0 && $# -ne 1 ]]; then
  dv::usage
  exit 1
fi

if [[ "${KEEP}" -eq 1 && $# -gt 1 ]]; then
  dv::usage
  exit 1
fi

WORKSPACE_INPUT="${1:-}"
dv::set_profile_volume_vars "${PROFILE_NAME}"

if [[ "${KEEP}" -eq 1 ]]; then
  CONTAINER_NAME="devbox-${PROFILE_NAME}-keep"
  OTHER_CONTAINER_NAME="devbox-${PROFILE_NAME}"
else
  CONTAINER_NAME="devbox-${PROFILE_NAME}"
  OTHER_CONTAINER_NAME="devbox-${PROFILE_NAME}-keep"
fi

if [[ -n "${WORKSPACE_INPUT}" && ! -d "${WORKSPACE_INPUT}" ]]; then
  printf '%s\n' "❌ Workspace path does not exist or is not a directory: ${WORKSPACE_INPUT}" >&2
  exit 1
fi

if ! [[ "${MEMORY_GB}" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' '❌ memory-gb must be a positive integer.' >&2
  exit 1
fi

if [[ -n "${HOST_PORT}" ]] && { ! [[ "${HOST_PORT}" =~ ^[0-9]+$ ]] || (( HOST_PORT < 1 || HOST_PORT > 65535 )); }; then
  printf '%s\n' '❌ host-port must be an integer between 1 and 65535.' >&2
  exit 1
fi

if ! [[ "${CPU_CORES}" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' '❌ cpu-cores must be a positive integer.' >&2
  exit 1
fi

dv::validate_profile_name "${PROFILE_NAME}"

if [[ -z "${TARGET_PATH}" || "${TARGET_PATH}" != /* ]]; then
  printf '%s\n' '❌ target-path must be a non-empty absolute path.' >&2
  exit 1
fi

dv::ensure_container_backend_running

MEMORY="${MEMORY_GB}G"

# An ephemeral run is blocked while a kept container exists for the profile:
# both own the same volumes and would otherwise double-mount them.
if [[ "${KEEP}" -eq 0 ]]; then
  KEPT_STATUS="$(dv::container_status "${OTHER_CONTAINER_NAME}")"
  if [[ -n "${KEPT_STATUS}" ]]; then
    printf '%s\n' "❌ Profile '${PROFILE_NAME}' has a kept container. Run it with -k, or remove it using the stop command's -D -v ${PROFILE_NAME} option, before starting an ephemeral devbox for this profile." >&2
    exit 1
  fi
fi

STATUS="$(dv::container_status "${CONTAINER_NAME}")"

if [[ -n "${WORKSPACE_INPUT}" ]]; then
  WORKSPACE="$(dv::resolve_workspace_path "${WORKSPACE_INPUT}")"

  if [[ "${TARGET_SET}" -eq 1 ]]; then
    MOUNT_TARGET="${TARGET_PATH}"
  else
    PROJECT_NAME="$(basename -- "${WORKSPACE}")"
    # The only path whose basename is unusable is the filesystem root
    # itself; fall back to a fixed name there.
    if [[ -z "${PROJECT_NAME}" || "${PROJECT_NAME}" == '/' ]]; then
      PROJECT_NAME='root'
    fi
    MOUNT_TARGET="/workspace/${PROJECT_NAME}"
  fi
else
  MOUNT_TARGET="${TARGET_PATH}"
fi

if [[ "${STATUS}" == 'running' ]]; then
  PROBE_DEST="$(dv::workspace_target_path "${CONTAINER_NAME}")"
  if [[ -z "${PROBE_DEST}" ]]; then
    PROBE_DEST="${MOUNT_TARGET}"
  fi
  EXISTING_WORKSPACE="$(dv::container_mount_source "${CONTAINER_NAME}" "${PROBE_DEST}")"

  if [[ -n "${EXISTING_WORKSPACE}" ]]; then
    printf '%s\n' "❌ Profile '${PROFILE_NAME}' is already running with workspace ${EXISTING_WORKSPACE} mounted at ${PROBE_DEST}." >&2
  else
    printf '%s\n' "❌ Profile '${PROFILE_NAME}' is already running, but no mount was found at ${PROBE_DEST}." >&2
  fi

  printf '%s\n' 'Stop the running profile first, then rerun with your desired settings.' >&2
  exit 1
fi

if [[ "${KEEP}" -eq 1 ]]; then
  # A kept run is likewise blocked while the profile's ephemeral container
  # runs — same double-mount conflict.
  OTHER_STATUS="$(dv::container_status "${OTHER_CONTAINER_NAME}")"
  if [[ "${OTHER_STATUS}" == 'running' ]]; then
    PROBE_DEST="$(dv::workspace_target_path "${OTHER_CONTAINER_NAME}")"
    if [[ -z "${PROBE_DEST}" ]]; then
      PROBE_DEST="${MOUNT_TARGET}"
    fi
    EXISTING_WORKSPACE="$(dv::container_mount_source "${OTHER_CONTAINER_NAME}" "${PROBE_DEST}")"

    if [[ -n "${EXISTING_WORKSPACE}" ]]; then
      printf '%s\n' "❌ Profile '${PROFILE_NAME}' is already running with workspace ${EXISTING_WORKSPACE} mounted at ${PROBE_DEST}." >&2
    else
      printf '%s\n' "❌ Profile '${PROFILE_NAME}' is already running, but no mount was found at ${PROBE_DEST}." >&2
    fi

    printf '%s\n' 'Stop the running profile first, then rerun with your desired settings.' >&2
    exit 1
  fi
fi

if [[ "${KEEP}" -eq 1 && -n "${STATUS}" ]]; then
  # A stopped kept container exists: resume it as-is (preserving in-container
  # changes) rather than recreating it.
  KEPT_PORT="$(dv::container_ssh_host_port "${CONTAINER_NAME}")"
  if [[ -n "${KEPT_PORT}" ]]; then
    CONFLICT_NAME="$(dv::find_port_conflict "${KEPT_PORT}" "${CONTAINER_NAME}" running)" || true
    if [[ -n "${CONFLICT_NAME:-}" ]]; then
      CONFLICT_PROFILE="$(dv::profile_name_from_container_name "${CONFLICT_NAME}")"
      printf '%s\n' "❌ Profile '${PROFILE_NAME}' can't resume: port ${KEPT_PORT} is already in use by running profile '${CONFLICT_PROFILE}'." >&2
      printf '%s\n' "Stop that profile first (./stop.sh -v ${CONFLICT_PROFILE}), then retry." >&2
      exit 1
    fi
  fi

  printf '%s\n' "⚠️  Resuming the kept container for profile '${PROFILE_NAME}'. workspace-path and -m/-c/-p/-t are ignored; the container keeps its original settings." >&2
  printf '%s\n' "🚀 Starting devbox for profile '${PROFILE_NAME}'..."
  dv::container_start "${CONTAINER_NAME}"
  dv::set_container_hostname "${CONTAINER_NAME}" "${PROFILE_NAME}"
  exit 0
fi

if [[ "$(dv::volume_exists "${HOME_VOLUME}")" != 1 || "$(dv::volume_exists "${DOCKER_VOLUME}")" != 1 ]]; then
  printf '%s\n' "❌ Profile '${PROFILE_NAME}' has not been initialized." >&2
  printf '%s\n' "Initialize this profile first, then try again." >&2
  exit 1
fi

if ! dv::image_exists "${DEVBOX_IMAGE}"; then
  printf '%s\n' "❌ Image ${DEVBOX_IMAGE} not found. Build it first: make build" >&2
  exit 1
fi

if [[ -z "${WORKSPACE_INPUT}" ]]; then
  printf '%s\n' "❌ workspace-path is required to start profile '${PROFILE_NAME}' for the first time." >&2
  printf '%s\n' "Provide a workspace-path, or omit it only to resume an existing kept container with -k." >&2
  exit 1
fi

if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT="$(dv::allocate_pool_port "${PORT_POOL_START}" "${PORT_POOL_END}" "${CONTAINER_NAME}")"
  printf '%s\n' "🔌 No -p given; auto-selected host port ${HOST_PORT} from the pool (${PORT_POOL_START}-${PORT_POOL_END})."
fi

if [[ "${KEEP}" -eq 1 ]]; then
  # New kept container: warn (don't block) on a port collision with another
  # profile, which would otherwise become a future resume conflict.
  PORT_CONFLICT_NAME="$(dv::find_port_conflict "${HOST_PORT}" "${CONTAINER_NAME}" all)" || true
  if [[ -n "${PORT_CONFLICT_NAME:-}" ]]; then
    PORT_CONFLICT_PROFILE="$(dv::profile_name_from_container_name "${PORT_CONFLICT_NAME}")"
    printf '%s\n' "⚠️  Warning: port ${HOST_PORT} is already used by devbox profile '${PORT_CONFLICT_PROFILE}' (running or kept). You may not be able to run both profiles at the same time. Use -p to choose a different port if needed." >&2
  fi
fi

if [[ -n "${STATUS}" ]]; then
  printf '%s\n' "🧹 Removing stale devbox for profile '${PROFILE_NAME}'..."
  dv::delete_container_if_present "${CONTAINER_NAME}"
fi

printf '%s\n' "🚀 Starting devbox for profile '${PROFILE_NAME}'..."
printf '%s\n' "📁 Bind-mounting ${WORKSPACE} → ${MOUNT_TARGET}"
dv::start_devbox_container "${CONTAINER_NAME}" "${KEEP}" "${MOUNT_TARGET}" "${HOST_PORT}" \
  "${HOME_VOLUME}" "${DOCKER_VOLUME}" "${WORKSPACE}" "${MEMORY}" "${CPU_CORES}" "${DEVBOX_IMAGE}"
dv::set_container_hostname "${CONTAINER_NAME}" "${PROFILE_NAME}"
