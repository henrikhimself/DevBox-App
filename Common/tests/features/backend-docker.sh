#!/usr/bin/env bash
# Docker backend for the dv:: helpers. Sourced by testenv.sh when
# DEVBOX_TEST_RUNTIME=docker. Self-contained: no dependency on repository code.
#
# Uses only the pinned `docker` command against the Engine selected by the
# caller's environment/context. It never switches contexts, starts a daemon, or
# removes anything it was not asked to remove by exact name. Real-runtime tests
# only: stub-based tests are Apple-specific (see applicability.tsv).

# ── Runtime detection ────────────────────────────────────────────────────────

if [[ -z "${DOCKER_CMD:-}" ]]; then
  if command -v docker >/dev/null 2>&1; then
    DOCKER_CMD='docker'
  else
    printf '%s\n' '❌ docker is not installed or not in PATH.' >&2
    exit 1
  fi
elif [[ "$(basename -- "${DOCKER_CMD}")" != 'docker' ]]; then
  printf '%s\n' "❌ DOCKER_CMD must name the 'docker' command. Got: ${DOCKER_CMD}" >&2
  exit 1
fi

# shellcheck disable=SC2034 # read by feature scripts
TENV_RUNTIME_CMD="${DOCKER_CMD}"

# Ensure an image is available locally, pulling it if absent.
dv::ensure_image() {
  local image="${1}"
  "${DOCKER_CMD}" image inspect "${image}" >/dev/null 2>&1 && return 0
  "${DOCKER_CMD}" image pull "${image}" >/dev/null 2>&1
}

# Run a container detached. All arguments are forwarded to 'docker container
# run -d' (flags, image, cmd). Do NOT pass --rm; use dv::container_rm in the
# dv::cleanup trap instead.
dv::container_run_detached() {
  "${DOCKER_CMD}" container run -d "$@" >/dev/null
}

# Create a stopped container.
#   $1 — container name, $2 — image, $3+ — optional cmd args
dv::container_create() {
  local name="${1}"
  local image="${2}"
  local output
  if ! output="$("${DOCKER_CMD}" container create --name "${name}" "${image}" "${@:3}" 2>&1)"; then
    printf 'dv::container_create failed for %s: %s\n' "${name}" "${output}" >&2
    return 1
  fi
}

# Force-remove one or more containers (running or stopped), ignoring absent ones.
dv::container_rm() {
  local name
  for name in "$@"; do
    if ! dv::container_exists "${name}"; then
      continue
    fi

    local output
    output="$("${DOCKER_CMD}" container rm --force "${name}" 2>&1)" && continue
    printf '%s\n' "${output}" >&2
  done
}

# Stop one or more running containers, ignoring ones already stopped or absent.
dv::container_stop() {
  local name
  for name in "$@"; do
    if ! dv::container_is_running "${name}"; then
      continue
    fi

    local output
    output="$("${DOCKER_CMD}" container stop "${name}" 2>&1)" && continue
    printf '%s\n' "${output}" >&2
  done
}

# Print the container's mounts as tab-separated "source<TAB>destination" lines
# (all mount types). Empty when the container does not exist.
dv::container_mounts() {
  local name="${1}"
  local json

  json="$("${DOCKER_CMD}" container inspect "${name}" 2>/dev/null)" || return 0

  printf '%s' "${json}" | jq -r '.[0].Mounts[]? | "\(.Source)\t\(.Destination)"'
}

dv::container_is_running() {
  local name="${1}"
  local status
  status="$(dv::_container_status "${name}")"
  [[ "${status}" == 'running' ]]
}

dv::container_exists() {
  local name="${1}"
  local status
  status="$(dv::_container_status "${name}")"
  [[ -n "${status}" ]]
}

# Print newline-separated names of currently running devbox-* containers.
dv::running_devbox_names() {
  "${DOCKER_CMD}" container ls --filter status=running --format '{{.Names}}' | grep '^devbox-' || true
}

# Print newline-separated names of devbox-* containers in any state.
dv::all_devbox_names() {
  "${DOCKER_CMD}" container ls --all --format '{{.Names}}' | grep '^devbox-' || true
}

# Print newline-separated names of devbox-* volumes.
dv::all_devbox_volume_names() {
  "${DOCKER_CMD}" volume ls --format '{{.Name}}' | grep '^devbox-' || true
}

# Remove one or more volumes, ignoring absent ones.
dv::volume_rm() {
  local v
  for v in "$@"; do
    if ! dv::volume_exists "${v}"; then
      continue
    fi

    local output
    output="$("${DOCKER_CMD}" volume rm "${v}" 2>&1)" && continue
    printf '%s\n' "${output}" >&2
  done
}

dv::volume_exists() {
  local name="${1}"
  "${DOCKER_CMD}" volume inspect "${name}" >/dev/null 2>&1
}

# ── Internal helpers ─────────────────────────────────────────────────────────

# 'running', 'stopped' (created/exited), 'other', or empty when absent.
dv::_container_status() {
  local name="${1}"
  local json

  # Container-typed inspect: an image or volume with the same name never counts.
  json="$("${DOCKER_CMD}" container inspect "${name}" 2>/dev/null)" || return 0

  printf '%s' "${json}" | jq -r '.[0].State.Status // empty | if . == "running" then "running" elif . == "exited" or . == "created" then "stopped" else "other" end'
}
