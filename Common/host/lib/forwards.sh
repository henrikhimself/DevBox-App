#!/usr/bin/env bash
# SSH port-forward state and policy, shared by all frontends. A forward's
# lifecycle is its ssh ControlMaster socket under /tmp/devbox-forwards-<uid>;
# discovery is a `ps` scan. Runtime-neutral: it never calls the container CLI.
# Sourced, never executed. Bash 3.2 compatible.

# Directory for this user's forward control sockets. Under /tmp (short,
# per-user via ${UID}) — not ~/.ssh and not $TMPDIR, both of which can exceed
# the ~104-byte Unix-socket sun_path limit ($TMPDIR on macOS is a long
# /var/folders/... path). /tmp is short on every platform.
dv::forward_socket_dir() {
  printf '%s' "/tmp/devbox-forwards-${UID}"
}

# Path to the control socket for one profile's forward. Colon-delimited:
# profile names are restricted to [a-zA-Z0-9_] by dv::validate_profile_name,
# so ':' is a safe, unambiguous separator.
dv::forward_socket_path() {
  local profile_name="${1}"
  local host_port="${2}"
  local container_port="${3}"
  local dir
  dir="$(dv::forward_socket_dir)"
  printf '%s' "${dir}/${profile_name}:${host_port}:${container_port}.sock"
}

# Prints the -S socket path of every live "ssh -M" devbox-forward process, via
# `ps` (not SSH's -O check). A privileged-port forward's master runs as root;
# `ps` sees it regardless of UID, whereas -O check/exit need a peer-UID match a
# normal user can't satisfy against a root-owned master.
dv::running_forward_sockets() {
  local dir
  dir="$(dv::forward_socket_dir)"
  ps -e -ww -o command= 2>/dev/null | awk -v dir="${dir}/" '
    { for (i = 1; i <= NF; i++)
        if ($i == "-S" && index($(i+1), dir) == 1) { print $(i+1) }
    }
  ' || true
}

# 0 if a live "ssh -M" process uses this exact control socket, else 1.
# Independent of container state.
dv::forward_is_active() {
  local socket_path="${1}"
  local running_sockets
  running_sockets="$(dv::running_forward_sockets)"
  printf '%s\n' "${running_sockets}" | grep -qxF "${socket_path}"
}

# Newline-separated "profile:host:container" list of every currently active
# forward, across all profiles (empty if none). This is the single source
# of truth for forward discovery — dv::list_forwards_for_profile,
# dv::find_forward_profiles_by_port, dv::close_all_forwards_for_profile, and
# dv::close_all_forwards are all built on top of it.
dv::list_all_forwards() {
  local sock
  local base
  local profile_name
  local host_port
  local container_port
  local running_sockets

  running_sockets="$(dv::running_forward_sockets)"
  while IFS= read -r sock; do
    [[ -z "${sock}" ]] && continue
    base="$(basename "${sock}" .sock)"
    profile_name="${base%%:*}"
    host_port="$(printf '%s' "${base}" | cut -d: -f2)"
    container_port="$(printf '%s' "${base}" | cut -d: -f3)"
    printf '%s\n' "${profile_name}:${host_port}:${container_port}"
  done <<< "${running_sockets}"
}

# Comma-separated "host:container" list of a profile's active forwards
# (empty string if none). Used by forward.sh -l.
dv::list_forwards_for_profile() {
  local profile_name="${1}"
  local line_profile
  local line_host
  local line_container
  local result=''
  local all_forwards

  all_forwards="$(dv::list_all_forwards)"
  while IFS=: read -r line_profile line_host line_container; do
    [[ -z "${line_profile}" || "${line_profile}" != "${profile_name}" ]] && continue
    if [[ -n "${result}" ]]; then
      result+=","
    fi
    result+="${line_host}:${line_container}"
  done <<< "${all_forwards}"

  printf '%s' "${result}"
}

# Newline-separated profile names with a currently-live forward matching
# this exact host:container port pair (any profile). Used by forward.sh's
# -D auto-detect when -v is omitted.
dv::find_forward_profiles_by_port() {
  local host_port="${1}"
  local container_port="${2}"
  local line_profile
  local line_host
  local line_container
  local all_forwards

  all_forwards="$(dv::list_all_forwards)"
  while IFS=: read -r line_profile line_host line_container; do
    [[ -z "${line_profile}" ]] && continue
    if [[ "${line_host}" == "${host_port}" && "${line_container}" == "${container_port}" ]]; then
      printf '%s\n' "${line_profile}"
    fi
  done <<< "${all_forwards}"
}

# Closes one forward: plain `ssh -O exit` first, escalating to sudo only if
# that fails (which happens iff it was a sudo-created privileged-port forward —
# the failed plain attempt is the signal). Always removes the socket file.
dv::close_forward_socket() {
  local socket_path="${1}"
  local profile_name="${2}"
  local host_port="${3}"
  local container_port="${4}"
  local alias="devbox-${profile_name}"

  if ! ssh -S "${socket_path}" -O exit "${alias}" >/dev/null 2>&1; then
    printf '%s\n' "🔐 Closing port forward ${host_port}:${container_port} needs elevated privileges; sudo is needed."
    sudo ssh -S "${socket_path}" -O exit "${alias}" >/dev/null 2>&1 || true
  fi
  rm -f "${socket_path}"
  printf '%s\n' "🔌 Closed port forward ${host_port}:${container_port} for profile '${profile_name}'."
}

# Best-effort: closes every active forward for a profile. Used by stop.sh so
# a stopped container never leaves an orphaned tunnel behind, and by
# forward.sh's bulk-close (-D -v <profile>, no -p).
dv::close_all_forwards_for_profile() {
  local profile_name="${1}"
  local forwards
  local pair
  local host_port
  local container_port
  local sock

  forwards="$(dv::list_forwards_for_profile "${profile_name}")"
  [[ -z "${forwards}" ]] && return 0

  local IFS=','
  for pair in ${forwards}; do
    host_port="${pair%%:*}"
    container_port="${pair#*:}"
    sock="$(dv::forward_socket_path "${profile_name}" "${host_port}" "${container_port}")"
    dv::close_forward_socket "${sock}" "${profile_name}" "${host_port}" "${container_port}"
  done
}

# Best-effort: closes every active forward across every profile. Used by
# forward.sh's bulk-close (-D with no -p and no -v).
dv::close_all_forwards() {
  local line_profile
  local line_host
  local line_container
  local sock
  local all_forwards

  all_forwards="$(dv::list_all_forwards)"
  while IFS=: read -r line_profile line_host line_container; do
    [[ -z "${line_profile}" ]] && continue
    sock="$(dv::forward_socket_path "${line_profile}" "${line_host}" "${line_container}")"
    dv::close_forward_socket "${sock}" "${line_profile}" "${line_host}" "${line_container}"
  done <<< "${all_forwards}"
}
