#!/usr/bin/env bash
# Docker runtime adapter for devbox-docker: everything that touches the `docker`
# CLI or its JSON schema. Sourced by Docker/shared.sh, never executed. Same
# interface as AppleContainer/runtime/adapter.sh.
#
# Host/engine preconditions run ONCE when this file is sourced, before any
# profile resource is touched (native Linux amd64, pinned `docker` CLI, local
# Unix-socket endpoint, rootful Engine, no userns-remap). Nothing is started,
# switched or reconfigured. Launch paths additionally require /dev/fuse and
# /dev/net/tun.
#
# Object operations are type-specific (`docker container|image|volume ...`) so
# an image or volume that shares a container's name can never satisfy a
# container lookup. Absent (rc 0/1) is kept separate from daemon, permission or
# parse errors (rc 2 with a message): when an inspect fails, a successful
# listing decides; the CLI's error wording is never parsed.

_HJ_DOCKER_RUNTIME_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Frontend pin: default image tag. Current tag centralized in
# Common/image/tag.txt; an env DEVBOX_DEFAULT_IMAGE overrides it for running
# only (the build reads tag.txt directly via the override keyword, above).
# shellcheck disable=SC2034 # read by the shared command bodies
if [[ -z "${DEVBOX_DEFAULT_IMAGE:-}" ]]; then
  _HJ_DOCKER_TAG_FILE="${_HJ_DOCKER_RUNTIME_DIR}/../../Common/image/tag.txt"
  DEVBOX_DEFAULT_IMAGE="localhost:5000/hj/devbox-docker:$(cat "${_HJ_DOCKER_TAG_FILE}")"
fi
# shellcheck disable=SC2034 # read by forward.sh
DEVBOX_RUNTIME_SESSION_HINT="the Docker context and socket access of your normal user"

# shellcheck source=preflight.sh
source "${_HJ_DOCKER_RUNTIME_DIR}/preflight.sh"
dv::check build || exit 1

# ---- Launch prerequisites ----------------------------------------------------

# Re-validates everything a container (re)start needs, including the two host
# devices. Never changes host state.
dv::docker_require_launch() {
  dv::check launch || return 1
}

# Preflight already ran when this adapter was sourced (no daemon is ever
# started by DevBox), so this is a no-op kept for interface parity.
dv::ensure_container_backend_running() {
  return 0
}

# ---- Raw lookups --------------------------------------------------------------

# Newline-separated container names: scope 'all' or 'running'. rc 2 + message on
# failure (never masked).
dv::list_container_ids() {
  local scope="${1}"
  local out
  local -a args=(container ls --format '{{.Names}}')

  if [[ "${scope}" == 'all' ]]; then
    args=(container ls --all --format '{{.Names}}')
  else
    args=(container ls --filter status=running --format '{{.Names}}')
  fi

  if ! out="$("${DOCKERPF_CMD}" "${args[@]}" 2>&1)"; then
    printf '%s\n' "❌ docker ${args[*]} failed: ${out}" >&2
    return 2
  fi
  printf '%s\n' "${out}"
}

# Status: 0 = JSON on stdout, 1 = absent, 2 = runtime error (message on stderr).
dv::container_inspect_json() {
  local name="${1}"
  local json
  local names

  if json="$("${DOCKERPF_CMD}" container inspect "${name}" 2>/dev/null)"; then
    printf '%s' "${json}"
    return 0
  fi

  names="$(dv::list_container_ids all)" || return 2
  if printf '%s\n' "${names}" | grep -qxF -- "${name}"; then
    printf '%s\n' "❌ docker container inspect failed for '${name}', which is listed." >&2
    return 2
  fi
  return 1
}

# Newline-separated names of all volumes. rc 2 + message on failure.
dv::all_volume_names() {
  local out

  if ! out="$("${DOCKERPF_CMD}" volume ls --format '{{.Name}}' 2>&1)"; then
    printf '%s\n' "❌ docker volume ls failed: ${out}" >&2
    return 2
  fi
  printf '%s\n' "${out}"
}

# Prints 1 (exists) or 0 (absent); rc 2 with a message when the runtime fails.
dv::volume_exists() {
  local volume_name="${1}"
  local names

  if "${DOCKERPF_CMD}" volume inspect "${volume_name}" >/dev/null 2>&1; then
    printf '%s' '1'
    return 0
  fi

  names="$(dv::all_volume_names)" || return 2
  if printf '%s\n' "${names}" | grep -qxF -- "${volume_name}"; then
    printf '%s\n' "❌ docker volume inspect failed for '${volume_name}', which is listed." >&2
    return 2
  fi
  printf '%s' '0'
}

# 0 present, 1 absent, 2 error (message on stderr). Image-only lookup.
dv::image_exists() {
  local image="${1}"
  local out

  if "${DOCKERPF_CMD}" image inspect "${image}" >/dev/null 2>&1; then
    return 0
  fi
  # A working listing proves the daemon is reachable and the image is absent.
  if ! out="$("${DOCKERPF_CMD}" image ls --quiet "${image}" 2>&1)"; then
    printf '%s\n' "❌ docker image ls failed: ${out}" >&2
    return 2
  fi
  [[ -n "${out}" ]] && return 0
  return 1
}

# ---- Normalized metadata ------------------------------------------------------

# One record from a single inspect:
#   state<TAB>workspace_target_label<TAB>ssh_host_port<TAB>workspace_mount_source
# state: running | stopped (created, exited) | other (paused, restarting, dead,
# removing). ssh_host_port is the first CONFIGURED 2222/tcp host port (stopped
# containers included; IPv4/IPv6 bindings collapse to the first). Absent: four
# empty fields, rc 0. Error: rc 2. $2 optionally overrides the mount lookup
# destination (default: the workspace-target label).
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
    | ($c.Config.Labels["devbox.workspace-target"] // "") as $target
    | (if $has_dest == "1" then $dest else $target end) as $d
    | ($c.State.Status // "") as $s
    | [ (if $s == "" then ""
         elif $s == "running" then "running"
         elif ($s == "exited" or $s == "created") then "stopped"
         else "other" end),
        $target,
        ([$c.HostConfig.PortBindings["2222/tcp"][]? | select((.HostPort // "") != "") | .HostPort] | (.[0] // "")),
        ([$c.Mounts[]? | select(.Destination == $d) | .Source] | (.[0] // "")) ]
    | join("\t")'; then
    printf '%s\n' "❌ Could not parse 'docker container inspect ${name}' output." >&2
    return 2
  fi
}

# Newline-separated devbox-* container names; empty = none; rc 2 on failure.
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

# ---- Object operations ----------------------------------------------------------

dv::volume_create() {
  "${DOCKERPF_CMD}" volume create "${1}" >/dev/null
}

dv::delete_volume_if_present() {
  local volume_name="${1}"
  local output
  local exists

  exists="$(dv::volume_exists "${volume_name}")" || return 2
  if [[ "${exists}" == '0' ]]; then
    return 0
  fi

  output="$("${DOCKERPF_CMD}" volume rm "${volume_name}" 2>&1)" && return 0

  printf '%s\n' "${output}" >&2
  return 1
}

# Start an existing (kept) container. Its devices were fixed at creation, so the
# host devices are re-checked first.
dv::container_start() {
  dv::docker_require_launch || return 1
  "${DOCKERPF_CMD}" container start "${1}"
}

dv::container_stop() {
  "${DOCKERPF_CMD}" container stop "${1}"
}

# Force-remove (running allowed).
dv::container_remove() {
  "${DOCKERPF_CMD}" container rm --force "${1}"
}

# Best-effort removal used by helper-container cleanup traps.
dv::remove_helper_quietly() {
  "${DOCKERPF_CMD}" container rm --force "${1}" >/dev/null 2>&1 || true
}

# The container's hostname is set after every start through `hostname` over
# exec (non-fatal, cosmetic); no --hostname launch flag is added.
dv::set_container_hostname() {
  local container_name="${1}"
  local profile_name="${2}"

  if ! "${DOCKERPF_CMD}" exec "${container_name}" hostname "devbox-${profile_name}" >/dev/null 2>&1; then
    printf '%s\n' "⚠️  Could not set in-container hostname for profile '${profile_name}' (cosmetic only; SSH is unaffected)." >&2
  fi
}

# ---- Launch paths ------------------------------------------------------------

# Approved launch flags for a normal guest start (root /init startup):
# --privileged plus the common --cap-add ALL baseline. The in-guest rootless
# dockerd needs mount/user-namespace operations and device access that Docker's
# default AppArmor, seccomp and masked /proc,/sys paths block even with all
# capabilities. No host Docker socket, no extra
# mounts/sysctls/namespaces, no Apple-only options.
# Result in the global array HJ_DOCKER_LAUNCH_FLAGS.
dv::docker_launch_flags() {
  HJ_DOCKER_LAUNCH_FLAGS=(
    --privileged
    --cap-add ALL
  )
}

# Start the devbox container detached.
# Args: name keep(0|1) workspace-target host-port home-vol docker-vol
#       workspace memory cpus image
dv::start_devbox_container() {
  local name="${1}" keep="${2}" target="${3}" host_port="${4}"
  local home_volume="${5}" docker_volume="${6}" workspace="${7}"
  local memory="${8}" cpus="${9}" image="${10}"
  local -a flags=(-d --name "${name}")

  dv::docker_require_launch || return 1
  dv::docker_launch_flags
  flags+=("${HJ_DOCKER_LAUNCH_FLAGS[@]}")
  if [[ "${keep}" -eq 0 ]]; then
    flags+=(--rm)
  fi

  "${DOCKERPF_CMD}" container run "${flags[@]}" \
    --label "devbox.workspace-target=${target}" \
    -p "${host_port}:2222" \
    -v "${home_volume}:/home" \
    -v "${docker_volume}:/data/docker" \
    -v "${workspace}:${target}" \
    --memory "${memory}" \
    --cpus "${cpus}" \
    "${image}"
}

# Archive helper: bypasses /init (entrypoint replaced by bash), so it gets ONLY
# its volume/bind mounts. No daemon-start privileges, devices or published ports.
# Args: name image script [src:dst ...] -- [script-arg ...]
dv::run_helper_container() {
  local name="${1}" image="${2}" script="${3}"
  shift 3
  local -a mounts=()
  while [[ $# -gt 0 && "${1}" != '--' ]]; do
    mounts+=(-v "${1}")
    shift
  done
  [[ $# -gt 0 ]] && shift

  "${DOCKERPF_CMD}" container run --rm --name "${name}" \
    "${mounts[@]}" \
    --entrypoint /bin/bash \
    "${image}" -c "${script}" "$@"
}
