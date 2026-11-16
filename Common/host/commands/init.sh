#!/usr/bin/env bash
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/init.sh,
# Docker/init.sh), which has already sourced its shared.sh (adapter + libraries).

dv::usage() {
  cat <<'EOF'
Usage: [profile-name]

Argument:
  profile-name   Optional name of the devbox profile to initialize, default: home
EOF
}

dv::ensure_volume() {
  local volume_name="${1}"
  local volume_exists

  volume_exists="$(dv::volume_exists "${volume_name}")"
  if [[ "${volume_exists}" == '1' ]]; then
    return 0
  fi

  dv::volume_create "${volume_name}"
}

if [[ $# -gt 1 ]]; then
  dv::usage
  exit 1
fi

PROFILE_NAME="${1:-home}"

dv::validate_profile_name "${PROFILE_NAME}"

dv::set_profile_volume_vars "${PROFILE_NAME}"

printf '%s\n' "📦 Initializing profile: ${PROFILE_NAME}"
dv::ensure_volume "${HOME_VOLUME}"
dv::ensure_volume "${DOCKER_VOLUME}"
printf '%s\n' "✅ Profile '${PROFILE_NAME}' is ready."
