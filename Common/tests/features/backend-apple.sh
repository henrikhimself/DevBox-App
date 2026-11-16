#!/usr/bin/env bash
# Apple Container backend for the dv:: helpers. Sourced by testenv.sh when
# DEVBOX_TEST_RUNTIME=apple. Self-contained: no dependency on repository code.

# ── Runtime detection ────────────────────────────────────────────────────────

if [[ -z "${CONTAINER_CMD:-}" ]]; then
  if command -v container >/dev/null 2>&1; then
    CONTAINER_CMD='container'
  else
    printf '%s\n' '❌ Apple Container is not installed or not in PATH. Install Apple Container and try again.' >&2
    exit 1
  fi
else
  # Test override: a pre-set CONTAINER_CMD is accepted only when it names a
  # 'container' stub (a test helper binary), never a different runtime.
  if [[ "$(basename -- "${CONTAINER_CMD}")" != 'container' ]]; then
    printf '%s\n' "❌ CONTAINER_CMD must name the 'container' command (test stubs must be named 'container'). Got: ${CONTAINER_CMD}" >&2
    exit 1
  fi
fi
# shellcheck disable=SC2034 # read by feature scripts
TENV_RUNTIME_CMD="${CONTAINER_CMD}"

# Ensure an image is available locally, pulling it if absent.
dv::ensure_image() {
  local image="${1}"
  "${CONTAINER_CMD}" image inspect "${image}" >/dev/null 2>&1 && return 0
  "${CONTAINER_CMD}" image pull "${image}" >/dev/null 2>&1
}

# Run a container detached. All arguments are forwarded to Apple Container's
# 'run -d' command (flags, image, cmd).
# Do NOT pass --rm; use dv::container_rm in the dv::cleanup trap instead.
dv::container_run_detached() {
  "${CONTAINER_CMD}" run -d "$@" >/dev/null
}

# Create a stopped container.
#   $1 — container name
#   $2 — image
#   $3+ — optional cmd args (passed to Apple Container's 'create' subcommand)
#
# Apple Container's 'create' subcommand leaves the container stopped
# (verified against apple/container's
# Sources/ContainerCommands/Container/ContainerCreate.swift).
dv::container_create() {
  local name="${1}"
  local image="${2}"
  local output
  if ! output="$("${CONTAINER_CMD}" create --name "${name}" "${image}" "${@:3}" 2>&1)"; then
    printf 'dv::container_create failed for %s: %s\n' "${name}" "${output}" >&2
    return 1
  fi
}

# Force-remove one or more containers (running or stopped), ignoring not-found.
dv::container_rm() {
  local name
  for name in "$@"; do
    # Check existence first rather than pattern-matching "not found" error
    # text.
    if ! dv::container_exists "${name}"; then
      continue
    fi

    local output
    output="$("${CONTAINER_CMD}" delete --force "${name}" 2>&1)" && continue
    # Non-fatal: print but continue
    printf '%s\n' "${output}" >&2
  done
}

# Stop one or more running containers, ignoring ones already stopped or
# nonexistent.
dv::container_stop() {
  local name
  for name in "$@"; do
    if ! dv::container_is_running "${name}"; then
      continue
    fi

    local output
    output="$("${CONTAINER_CMD}" stop "${name}" 2>&1)" && continue
    # Non-fatal: print but continue
    printf '%s\n' "${output}" >&2
  done
}

# Print the container's mounts as tab-separated "source<TAB>destination" lines
# (all mount types). Empty when the container does not exist. Used by tests
# that need to verify what run.sh actually mounted, independent of labels.
dv::container_mounts() {
  local name="${1}"
  local json

  json="$("${CONTAINER_CMD}" inspect "${name}" 2>/dev/null)" || return 0

  printf '%s' "${json}" | jq -r '.[0].configuration.mounts[]? | "\(.source)\t\(.destination)"'
}

# Returns 0 if the named container is currently running, 1 otherwise.
dv::container_is_running() {
  local name="${1}"
  local status
  status="$(dv::_container_status "${name}")"
  [[ "${status}" == 'running' ]]
}

# Returns 0 if the named container exists in any state, 1 otherwise.
dv::container_exists() {
  local name="${1}"
  local status
  status="$(dv::_container_status "${name}")"
  [[ -n "${status}" ]]
}

# Print newline-separated names of currently running devbox-* containers.
dv::running_devbox_names() {
  "${CONTAINER_CMD}" list --format json | jq -r '.[] | select(.status.state == "running") | .id' \
    | grep '^devbox-' || true
}

# Print newline-separated names of devbox-* containers in any state (running
# or stopped).
dv::all_devbox_names() {
  # --all is required: `container list` defaults to running-only.
  "${CONTAINER_CMD}" list --all --format json | jq -r '.[].id' | grep '^devbox-' || true
}

# Print newline-separated names of devbox-* volumes.
dv::all_devbox_volume_names() {
  "${CONTAINER_CMD}" volume ls --format json | jq -r '.[].id' | grep '^devbox-' || true
}

# Remove one or more volumes, ignoring not-found errors.
dv::volume_rm() {
  local v
  for v in "$@"; do
    # Check existence first rather than pattern-matching "not found" error
    # text (Apple Container's volume delete reports "failed to delete one or
    # more volumes: [...]").
    if ! dv::volume_exists "${v}"; then
      continue
    fi

    local output
    output="$("${CONTAINER_CMD}" volume rm "${v}" 2>&1)" && continue
    # Non-fatal: print but continue
    printf '%s\n' "${output}" >&2
  done
}

# Returns 0 if the named volume exists, 1 otherwise.
dv::volume_exists() {
  local name="${1}"
  "${CONTAINER_CMD}" volume inspect "${name}" >/dev/null 2>&1
}

# ── Internal helpers ─────────────────────────────────────────────────────────

# Returns a string describing the container state ('running', 'stopped', or
# empty when the container does not exist).
dv::_container_status() {
  local name="${1}"
  local json

  # Apple Container's inspect targets containers only, so an absent container
  # reports absent even though its volumes may share the name. (Gate on rc,
  # not on an empty result.)
  json="$("${CONTAINER_CMD}" inspect "${name}" 2>/dev/null)" || return 0

  printf '%s' "${json}" | jq -r '.[0].status.state // empty'
}

