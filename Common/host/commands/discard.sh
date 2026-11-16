#!/usr/bin/env bash
# shellcheck disable=SC2310 # dv::confirm intentionally returns non-zero when the user declines.
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/discard.sh,
# Docker/discard.sh), which has already sourced its shared.sh (adapter + libraries).

dv::require_jq

dv::usage() {
  cat <<'EOF'
Usage: [options] <profile-name>

Options:
  -y  Skip confirmation prompt and discard immediately
EOF
}

ASSUME_YES=0

while getopts ':y' opt; do
  case "${opt}" in
    y)
      ASSUME_YES=1
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

if [[ $# -ne 1 ]]; then
  dv::usage
  exit 1
fi

PROFILE_NAME="${1}"
dv::validate_profile_name "${PROFILE_NAME}"
dv::set_profile_volume_vars "${PROFILE_NAME}"

dv::ensure_container_backend_running

for container_name in "devbox-${PROFILE_NAME}" "devbox-${PROFILE_NAME}-keep"; do
  container_status="$(dv::container_status "${container_name}")"
  if [[ "${container_status}" == 'running' ]]; then
    printf '%s\n' "❌ Profile '${PROFILE_NAME}' has a running container (${container_name}). Stop/remove it first." >&2
    exit 1
  fi
done

HAS_HOME_VOLUME=0
HAS_DOCKER_VOLUME=0
home_volume_exists="$(dv::volume_exists "${HOME_VOLUME}")"
docker_volume_exists="$(dv::volume_exists "${DOCKER_VOLUME}")"
if [[ "${home_volume_exists}" == '1' ]]; then
  HAS_HOME_VOLUME=1
fi
if [[ "${docker_volume_exists}" == '1' ]]; then
  HAS_DOCKER_VOLUME=1
fi

if [[ "${HAS_HOME_VOLUME}" -eq 0 && "${HAS_DOCKER_VOLUME}" -eq 0 ]]; then
  printf '%s\n' "❌ Profile '${PROFILE_NAME}' has no volumes to discard." >&2
  exit 1
fi

dv::confirm "Discard profile '${PROFILE_NAME}' and delete its volumes?" "${ASSUME_YES}" || exit 1

if [[ "${HAS_HOME_VOLUME}" -eq 1 ]]; then
  dv::delete_volume_if_present "${HOME_VOLUME}"
fi

if [[ "${HAS_DOCKER_VOLUME}" -eq 1 ]]; then
  dv::delete_volume_if_present "${DOCKER_VOLUME}"
fi

# Also remove the profile's ssh alias so 'ssh devbox-<profile>' no longer
# resolves against a dead port. No-op if the block does not exist.
dv::remove_ssh_host_block "${PROFILE_NAME}"

printf '%s\n' "✅ Discarded profile '${PROFILE_NAME}'."
