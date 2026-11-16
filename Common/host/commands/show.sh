#!/usr/bin/env bash
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/show.sh,
# Docker/show.sh), which has already sourced its shared.sh (adapter + libraries).

dv::require_jq

dv::usage() {
  cat <<'EOF'
Usage: no arguments

Shows all created devbox profiles (sorted) with:
  PROFILE STATUS SSH_PORT EXISTING_WORKSPACE TARGET_PATH

Every profile initialized by init.sh is listed, whether or not it has a
devbox container (running or stopped). A profile with no devbox container
shows status 'none' and '-' in the remaining columns.
EOF
}

if [[ $# -ne 0 ]]; then
  dv::usage
  exit 1
fi

dv::ensure_container_backend_running

ALL_PROFILE_NAMES="$(dv::all_profile_names)"
if [[ -z "${ALL_PROFILE_NAMES}" ]]; then
  printf '%s\n' '❌ No devbox profiles found.' >&2
  exit 1
fi

printf '%s\t%s\t%s\t%s\t%s\n' 'PROFILE' 'STATUS' 'SSH_PORT' 'EXISTING_WORKSPACE' 'TARGET_PATH'

while IFS= read -r profile_name; do
  if [[ -z "${profile_name}" ]]; then
    continue
  fi

  # One inspect per container: try the profile's container first, then its
  # kept container. dv::container_summary prints four empty fields when the
  # container doesn't exist, so an empty status means "not this one".
  summary="$(dv::container_summary "devbox-${profile_name}")"
  IFS=$'\t' read -r status target_path ssh_port existing_workspace <<< "${summary}"
  if [[ -z "${status}" ]]; then
    summary="$(dv::container_summary "devbox-${profile_name}-keep")"
    IFS=$'\t' read -r status target_path ssh_port existing_workspace <<< "${summary}"
  fi

  if [[ -z "${status}" ]]; then
    # Profile has been initialized but has no devbox container.
    printf '%s\t%s\t%s\t%s\t%s\n' "${profile_name}" 'none' '-' '-' '-'
    continue
  fi

  if [[ -z "${ssh_port}" ]]; then
    ssh_port='-'
  fi

  if [[ -z "${existing_workspace}" ]]; then
    existing_workspace='-'
  fi

  if [[ -z "${target_path}" ]]; then
    target_path='-'
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "${profile_name}" "${status}" "${ssh_port}" "${existing_workspace}" "${target_path}"
done <<< "${ALL_PROFILE_NAMES}"
