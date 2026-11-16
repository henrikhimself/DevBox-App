#!/usr/bin/env bash
# Runtime-neutral container metadata accessors, all derived from the adapter's
# single normalized record (dv::container_summary):
#   state<TAB>workspace_target_label<TAB>ssh_host_port<TAB>workspace_mount_source
# Absent container => empty fields and status 0; runtime error => status 2 (the
# adapter has already printed the message). Callers that assign with $(...) under
# `set -e` therefore stop on a runtime error; callers testing inside [[ ]] must
# assign first (see backup.sh/restore.sh). Sourced, never executed. Bash 3.2 safe.

# Field N (1-4) of the summary of container $1 (optional mount destination $2).
dv::_summary_field() {
  local field="${1}"
  shift
  local summary

  summary="$(dv::container_summary "$@")" || return 2
  printf '%s' "${summary}" | cut -f"${field}"
}

dv::container_status() {
  dv::_summary_field 1 "${1}"
}

dv::workspace_target_path() {
  dv::_summary_field 2 "${1}"
}

dv::container_ssh_host_port() {
  dv::_summary_field 3 "${1}"
}

# Workspace mount source at destination $2 (default: the workspace label).
dv::container_mount_source() {
  dv::_summary_field 4 "${1}" "${2}"
}

# Removes a container (running allowed) when it exists.
dv::delete_container_if_present() {
  local name="${1}"
  local output
  local status

  # Check existence first (the "not found" text varies).
  status="$(dv::container_status "${name}")" || return 2
  if [[ -z "${status}" ]]; then
    return 0
  fi

  output="$(dv::container_remove "${name}" 2>&1)" && return 0

  printf '%s\n' "${output}" >&2
  return 1
}
