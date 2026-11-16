#!/usr/bin/env bash
# Apple Container host/backend preflight for devbox-apple. Read-only: never
# starts, reconfigures or switches the backend, or creates anything. Rejects
# (never works around) unsupported configurations.
#
# Library use:   source preflight.sh; dv::check <build|launch>
# CLI use:       preflight.sh <build|launch>
#
# A build needs a native arm64 macOS host, the pinned `container` CLI, jq and a
# running backend. A launch needs everything a build does.

dv::fail() { printf '❌ %s\n' "$1" >&2; return 1; }

dv::resolve_cmd() {
  local cmd="${CONTAINER_CMD:-container}"
  [[ "$(basename -- "${cmd}")" == 'container' ]] || {
    dv::fail "CONTAINER_CMD must name the 'container' command. Got: ${cmd}"; return 1; }
  command -v "${cmd}" >/dev/null 2>&1 || { dv::fail "container CLI not found: ${cmd}"; return 1; }
  APPLEPF_CMD="${cmd}"
}

dv::host_os()  { uname -s; }
dv::host_arch() { uname -m; }

dv::backend_status() {
  # Parse the status row of `container system status` the same way the
  # lifecycle backend helper does.
  "${CONTAINER_CMD:-container}" system status 2>/dev/null \
    | awk '$1 == "status" { print $2; exit }' || true
}

dv::check() {
  local mode="${1:-build}"
  case "${mode}" in
    build|launch) ;;
    *) dv::fail "unknown preflight mode: ${mode}"; return 1 ;;
  esac

  local os arch status tool
  os="$(dv::host_os)";  [[ "${os}" == 'Darwin' ]]   || { dv::fail "unsupported host OS '${os}'; devbox-apple requires macOS (Darwin)."; return 1; }
  arch="$(dv::host_arch)"; [[ "${arch}" == 'arm64' ]] || { dv::fail "unsupported host architecture '${arch}'; devbox-apple requires Apple silicon (arm64)."; return 1; }

  for tool in container jq; do
    command -v "${tool}" >/dev/null 2>&1 || { dv::fail "required host tool not found: ${tool}"; return 1; }
  done

  dv::resolve_cmd || return 1

  status="$(dv::backend_status)"; [[ "${status}" == 'running' ]] || {
    dv::fail "Apple Container backend is not running (status: '${status}'). Start it with: container system start"; return 1; }
  APPLEPF_CMD="${APPLEPF_CMD:-${CONTAINER_CMD:-container}}"

  return 0
}

# CLI entry: run the requested mode.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -u
  dv::check "${1:-build}" || exit 1
fi
