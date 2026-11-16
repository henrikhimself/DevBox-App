#!/usr/bin/env bash
# Apple Container runtime adapter: everything that touches the `container` CLI
# or its JSON schema. Sourced by AppleContainer/shared.sh, never executed.
# (Function names are unchanged in this mechanical step; the normalized
# adapter contract is introduced in P3-02/P3-03.)

# Frontend pin: default image tag. Current tag centralized in
# Common/image/tag.txt; an env DEVBOX_DEFAULT_IMAGE overrides it for running
# only (the build reads tag.txt directly via the override keyword, above).
# shellcheck disable=SC2034 # read by the shared command bodies
if [[ -z "${DEVBOX_DEFAULT_IMAGE:-}" ]]; then
  _HJ_APPLE_TAG_FILE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../Common/image/tag.txt"
  DEVBOX_DEFAULT_IMAGE="localhost:5000/hj/devbox-apple:$(cat "${_HJ_APPLE_TAG_FILE}")"
fi
# shellcheck disable=SC2034 # read by forward.sh
DEVBOX_RUNTIME_SESSION_HINT="Apple Container's per-user session"

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

dv::container_inspect_json() {
  local name="${1}"

  # Apple Container's inspect targets containers only, so an absent devbox
  # container reports absent even though its volumes share the name.
  #
  # Status: 0 = JSON on stdout, 1 = absent, 2 = runtime error (message on
  # stderr). The CLI's error text is not parsed (its wording is not a contract):
  # when inspect fails, the full container list decides. A name absent from a
  # list that was obtained successfully is absent; a failing list is an error.
  local json
  local names

  if json="$("${CONTAINER_CMD}" inspect "${name}" 2>/dev/null)"; then
    printf '%s' "${json}"
    return 0
  fi

  names="$(dv::list_container_ids all)" || return 2
  if printf '%s\n' "${names}" | grep -qxF -- "${name}"; then
    printf '%s\n' "❌ container inspect failed for '${name}', which is listed." >&2
    return 2
  fi
  return 1
}

# Newline-separated ids of containers: scope 'all' or 'running'. Status 2 and a
# message on stderr when the runtime or its JSON output fails (no masking).
dv::list_container_ids() {
  local scope="${1}"
  local json
  local filter='.[].id'
  local -a args=(list --format json)

  if [[ "${scope}" == 'all' ]]; then
    # --all is required: `container list` defaults to running-only.
    args=(list --all --format json)
  else
    filter='.[] | select(.status.state == "running") | .id'
  fi

  if ! json="$("${CONTAINER_CMD}" "${args[@]}" 2>&1)"; then
    printf '%s\n' "❌ container ${args[*]} failed: ${json}" >&2
    return 2
  fi
  if ! printf '%s' "${json}" | jq -r "${filter}"; then
    printf '%s\n' "❌ Could not parse 'container ${args[*]}' output." >&2
    return 2
  fi
}

# Prints 1 (exists) or 0 (absent); status 2 with a message when the runtime fails.
dv::volume_exists() {
  local volume_name="${1}"
  local names

  if "${CONTAINER_CMD}" volume inspect "${volume_name}" >/dev/null 2>&1; then
    printf '%s' '1'
    return 0
  fi

  # Failed inspect: absent or error? A successful listing decides.
  names="$(dv::all_volume_names)" || return 2
  if printf '%s\n' "${names}" | grep -qxF -- "${volume_name}"; then
    printf '%s\n' "❌ container volume inspect failed for '${volume_name}', which is listed." >&2
    return 2
  fi
  printf '%s' '0'
}

# Newline-separated names of all volumes on Apple Container. Status 2 on failure.
dv::all_volume_names() {
  local json

  if ! json="$("${CONTAINER_CMD}" volume ls --format json 2>&1)"; then
    printf '%s\n' "❌ container volume ls failed: ${json}" >&2
    return 2
  fi
  if ! printf '%s' "${json}" | jq -r '.[].id'; then
    printf '%s\n' "❌ Could not parse 'container volume ls' output." >&2
    return 2
  fi
}

# Normalized one-record summary from a single inspect. Prints
#   state<TAB>workspace_target_label<TAB>ssh_host_port<TAB>workspace_mount_source
# Absent container: four empty fields, status 0. Runtime error: status 2.
# Missing label/mounts/ports yield empty fields; several 2222/tcp bindings yield
# the first. $2 (optional) overrides the destination used for the mount lookup
# (default: the workspace-target label).
dv::container_summary() {
  local name="${1}"
  local json
  local rc
  local has_dest=0
  local dest=''

  if [[ $# -ge 2 ]]; then
    has_dest=1
    dest="${2}"
  fi

  if json="$(dv::container_inspect_json "${name}")"; then
    rc=0
  else
    rc=$?
  fi
  case "${rc}" in
    0) ;;
    1) printf '\t\t\t\n'; return 0 ;;
    *) return 2 ;;
  esac

  if ! printf '%s' "${json}" | jq -r --arg has_dest "${has_dest}" --arg dest "${dest}" '
    .[0] as $c
    | ($c.configuration.labels["devbox.workspace-target"] // "") as $target
    | (if $has_dest == "1" then $dest else $target end) as $d
    | [ ($c.status.state // ""),
        $target,
        ([$c.configuration.publishedPorts[]? | select(.containerPort == 2222 and ((.proto // "tcp") == "tcp")) | .hostPort] | (.[0] // "") | tostring),
        ([$c.configuration.mounts[]? | select(.destination == $d) | .source] | (.[0] // "")) ]
    | join("\t")'; then
    printf '%s\n' "❌ Could not parse 'container inspect ${name}' output." >&2
    return 2
  fi
}

dv::delete_volume_if_present() {
  local volume_name="${1}"
  local output
  local exists

  # Check existence first rather than matching "not found" error text.
  exists="$(dv::volume_exists "${volume_name}")"
  if [[ "${exists}" == '0' ]]; then
    return 0
  fi

  output="$("${CONTAINER_CMD}" volume rm "${volume_name}" 2>&1)" && return 0

  printf '%s\n' "${output}" >&2
  return 1
}

dv::ensure_container_backend_running() {
  local timeout_seconds=30
  local attempt
  local status

  status="$("${CONTAINER_CMD}" system status 2>/dev/null | awk '$1 == "status" { print $2; exit }' || true)"
  if [[ "${status}" == 'running' ]]; then
    return 0
  fi

  printf '%s\n' '⏳ Container backend is not running. Starting it...'
  "${CONTAINER_CMD}" system start

  for (( attempt = 0; attempt < timeout_seconds; attempt++ )); do
    status="$("${CONTAINER_CMD}" system status 2>/dev/null | awk '$1 == "status" { print $2; exit }' || true)"
    if [[ "${status}" == 'running' ]]; then
      return 0
    fi
    sleep 1
  done

  printf '%s\n' "❌ Container backend did not report 'running' within ${timeout_seconds}s. Check the Apple Container app (or run 'container system status' manually)." >&2
  return 1
}

# Sets the in-container hostname to "devbox-<profile>" via `hostname` over exec.
# Must run after every start: Apple Container does not set a name at creation
# that survives a kept container's stop/start (a fresh UTS namespace resets
# it). Needs the full capability set (run.sh's --cap-add ALL). Non-fatal and
# cosmetic; SSH is unaffected on failure.
dv::set_container_hostname() {
  local container_name="${1}"
  local profile_name="${2}"

  if ! "${CONTAINER_CMD}" exec "${container_name}" hostname "devbox-${profile_name}" >/dev/null 2>&1; then
    printf '%s\n' "⚠️  Could not set in-container hostname for profile '${profile_name}' (cosmetic only; SSH is unaffected)." >&2
  fi
}

# Force-delete: Apple Container refuses running containers otherwise.
dv::container_remove() {
  "${CONTAINER_CMD}" delete --force "${1}"
}

# Newline-separated devbox-* container names. Empty output is success (none);
# a runtime failure is status 2 with a message (never masked).
dv::running_devbox_names() {
  local ids

  ids="$(dv::list_container_ids running)" || return 2
  printf '%s\n' "${ids}" | grep '^devbox-' || true
}

dv::all_devbox_names() {
  local ids

  ids="$(dv::list_container_ids all)" || return 2
  printf '%s\n' "${ids}" | grep '^devbox-' || true
}

# ---- Object operations (P3-02): the shared commands call only these. ----

# ---- Throwaway run flags (make run) -------------------------------------
# Single flag source for the interactive throwaway container (`make run`).
# The SSH publication is fixed in runtime/throwaway.sh; the remainder is the
# approved, fixed set defined once here so the Makefile never duplicates a flag.
dv::run_flags() {
  HJ_RUN_FLAGS=(--no-dns --cap-add ALL \
    --tmpfs /tmp --tmpfs /var/tmp --tmpfs /var/log --tmpfs /run/lock)
}

# ---- Object operations (P3-02): the shared commands call only these. ----

dv::image_exists() {
  "${CONTAINER_CMD}" image inspect "${1}" >/dev/null 2>&1
}

dv::volume_create() {
  "${CONTAINER_CMD}" volume create "${1}" >/dev/null
}

dv::container_start() {
  "${CONTAINER_CMD}" start "${1}"
}

dv::container_stop() {
  "${CONTAINER_CMD}" stop "${1}"
}

# Best-effort removal used by helper-container cleanup traps.
dv::remove_helper_quietly() {
  "${CONTAINER_CMD}" delete --force "${1}" >/dev/null 2>&1 || true
}

# Start the devbox container detached.
# Args: name keep(0|1) workspace-target host-port home-vol docker-vol
#       workspace memory cpus image
dv::start_devbox_container() {
  local name="${1}" keep="${2}" target="${3}" host_port="${4}"
  local home_volume="${5}" docker_volume="${6}" workspace="${7}"
  local memory="${8}" cpus="${9}" image="${10}"
  local -a flags=(-d --name "${name}")

  # Full capability set: required for the in-container hostname and for the
  # rootless Docker daemon inside the guest.
  flags+=(--cap-add ALL)
  if [[ "${keep}" -eq 0 ]]; then
    flags+=(--rm)
  fi

  "${CONTAINER_CMD}" run "${flags[@]}" \
    --label "devbox.workspace-target=${target}" \
    -p "${host_port}:2222" \
    -v "${home_volume}:/home" \
    -v "${docker_volume}:/data/docker" \
    -v "${workspace}:${target}" \
    --memory "${memory}" \
    --cpus "${cpus}" \
    "${image}"
}

# Run a throwaway helper container with the image's entrypoint replaced by bash.
# Args: name image script [src:dst ...] -- [script-arg ...]
# stdin/stdout/stderr are the caller's (callers detach or capture as needed).
dv::run_helper_container() {
  local name="${1}" image="${2}" script="${3}"
  shift 3
  local -a mounts=()
  while [[ $# -gt 0 && "${1}" != '--' ]]; do
    mounts+=(-v "${1}")
    shift
  done
  [[ $# -gt 0 ]] && shift

  "${CONTAINER_CMD}" run --rm --name "${name}" \
    "${mounts[@]}" \
    --entrypoint /bin/bash \
    "${image}" -c "${script}" "$@"
}
