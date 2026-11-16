#!/usr/bin/env bash
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/stop.sh,
# Docker/stop.sh), which has already sourced its shared.sh (adapter + libraries).

dv::require_jq

dv::usage() {
  cat <<'EOF'
Usage: [options]

Options:
  -v profile-name  Optional profile name selecting which devbox profile to stop; auto-detected if omitted and exactly one is running
  -D               Force-remove the kept container for a profile (requires -v); stops it first if running
EOF
}

FORCE_REMOVE=0

while getopts ':v:D' opt; do
  case "${opt}" in
    v)
      PROFILE_NAME="${OPTARG}"
      ;;
    D)
      FORCE_REMOVE=1
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

if [[ -n "${PROFILE_NAME:-}" ]]; then
  dv::validate_profile_name "${PROFILE_NAME}"
fi

dv::ensure_container_backend_running

if [[ "${FORCE_REMOVE}" -eq 1 ]]; then
  if [[ -z "${PROFILE_NAME:-}" ]]; then
    printf '%s\n' '❌ -D requires -v profile-name.' >&2
    exit 1
  fi

  KEPT_CONTAINER_NAME="devbox-${PROFILE_NAME}-keep"
  KEPT_STATUS="$(dv::container_status "${KEPT_CONTAINER_NAME}")"

  if [[ -z "${KEPT_STATUS}" ]]; then
    printf '%s\n' "❌ No kept container found for profile '${PROFILE_NAME}'." >&2
    exit 1
  fi

  if [[ "${KEPT_STATUS}" == 'running' ]]; then
    dv::container_stop "${KEPT_CONTAINER_NAME}"
  fi

  dv::delete_container_if_present "${KEPT_CONTAINER_NAME}"
  dv::close_all_forwards_for_profile "${PROFILE_NAME}"
  printf '%s\n' "✅ Removed kept container for profile '${PROFILE_NAME}'."
  exit 0
fi

dv::resolve_running_devbox "${PROFILE_NAME:-}"

dv::container_stop "${CONTAINER_NAME}"
dv::close_all_forwards_for_profile "${PROFILE_NAME}"
