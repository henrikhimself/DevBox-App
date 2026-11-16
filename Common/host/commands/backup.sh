#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2310,SC2312 # Helper command is intentionally single-quoted; status functions are predicates.
# Create a portable archive of a stopped profile's persistent volumes.
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/backup.sh,
# Docker/backup.sh), which has already sourced its shared.sh (adapter + libraries).

dv::usage() {
  cat <<'EOF'
Usage: backup.sh [-f] <profile-name> <backup.tar.gz>

Creates a gzip-compressed, restorable archive of the profile's persistent
/home volume. By default, only Docker named volumes stored under
/data/docker/volumes are included from the Docker state volume.

With -f, the backup includes the full /data/docker tree as well. In both
modes, the profile must not have a running container and the output file
must not already exist.

The backup never includes the workspace bind mount or any kept-container
filesystem layer. Restore the archive with ./restore.sh <profile-name>
<backup.tar.gz>.
EOF
}

dv::fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
}

FULL_BACKUP=0
while getopts ':f' opt; do
  case "${opt}" in
    f) FULL_BACKUP=1 ;;
    *)
      dv::usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -ne 2 ]]; then
  dv::usage
  exit 1
fi

PROFILE_NAME="${1}"
BACKUP_INPUT="${2}"
DEVBOX_IMAGE="${DEVBOX_IMAGE:-${DEVBOX_DEFAULT_IMAGE}}"
if [[ "${FULL_BACKUP}" -eq 1 ]]; then
  BACKUP_SCOPE='full'
else
  BACKUP_SCOPE='named-volumes'
fi

dv::validate_profile_name "${PROFILE_NAME}"
dv::require_jq
dv::set_profile_volume_vars "${PROFILE_NAME}"

[[ "${BACKUP_INPUT}" == *.tar.gz ]] || dv::fail "backup path must end in .tar.gz: ${BACKUP_INPUT}"
[[ ! -e "${BACKUP_INPUT}" ]] || dv::fail "backup file already exists: ${BACKUP_INPUT}"

BACKUP_DIR_INPUT="$(dirname -- "${BACKUP_INPUT}")"
[[ -d "${BACKUP_DIR_INPUT}" ]] || dv::fail "backup directory does not exist: ${BACKUP_DIR_INPUT}"
BACKUP_DIR="$(cd "${BACKUP_DIR_INPUT}" && pwd -P)"
BACKUP_BASENAME="$(basename -- "${BACKUP_INPUT}")"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_BASENAME}"
[[ -w "${BACKUP_DIR}" ]] || dv::fail "backup directory is not writable: ${BACKUP_DIR}"

dv::ensure_container_backend_running

for container_name in "devbox-${PROFILE_NAME}" "devbox-${PROFILE_NAME}-keep"; do
  container_state="$(dv::container_status "${container_name}")"
  if [[ "${container_state}" == 'running' ]]; then
    dv::fail "profile '${PROFILE_NAME}' has a running container (${container_name}). Stop it before backing up."
  fi
done

[[ "$(dv::volume_exists "${HOME_VOLUME}")" == '1' ]] \
  || dv::fail "profile '${PROFILE_NAME}' has no home volume. Initialize it first."
[[ "$(dv::volume_exists "${DOCKER_VOLUME}")" == '1' ]] \
  || dv::fail "profile '${PROFILE_NAME}' has no Docker volume. Initialize it first."
dv::image_exists "${DEVBOX_IMAGE}" \
  || dv::fail "image ${DEVBOX_IMAGE} not found. Build it first: make build"

HELPER_NAME="backup-${PROFILE_NAME}-$$"
SUCCESS=0
dv::cleanup() {
  if [[ "${SUCCESS}" -eq 0 ]]; then
    rm -f "${BACKUP_FILE}"
  fi
  dv::remove_helper_quietly "${HELPER_NAME}"
}
trap dv::cleanup EXIT

printf '📦 Backing up profile %q to %s...\n' "${PROFILE_NAME}" "${BACKUP_FILE}"
if [[ "${BACKUP_SCOPE}" == 'full' ]]; then
  printf '%s\n' '⏳ Archiving profile data (full Docker state); progress is reported every 5 MiB.'
else
  printf '%s\n' '⏳ Archiving profile data (home + Docker named volumes); progress is reported every 5 MiB.'
fi
# The helper only writes the archive and progress to its output streams. Detach its
# standard input so Apple Container does not install terminal signal forwarding
# (which can emit a harmless SIGWINCH/XPC error during long-running archives).
if ! dv::run_helper_container "${HELPER_NAME}" "${DEVBOX_IMAGE}" \
  'set -e
work_dir="$(mktemp -d)"
trap "rm -rf \"${work_dir}\"" EXIT
printf "format=devbox-profile-backup-v1\\nprofile=%s\\ncreated_utc=%s\\nscope=%s\\n" "$1" "$2" "$4" > "${work_dir}/manifest"
if [[ "$4" == full ]]; then
  tar --checkpoint=10240 --checkpoint-action="echo=⏳ Archived 5 MiB more..." \
    -C "${work_dir}" -czf "/backup/$3" manifest -C /backup-source home docker
else
  docker_source_dir="/backup-source/docker"
  mkdir -p "${work_dir}/docker/volumes"
  [[ -d "${docker_source_dir}/volumes" ]] || docker_source_dir="${work_dir}/docker"
  tar --checkpoint=10240 --checkpoint-action="echo=⏳ Archived 5 MiB more..." \
    -C "${work_dir}" -czf "/backup/$3" manifest docker \
    -C /backup-source home \
    --transform="s,^volumes,docker/volumes," -C "${docker_source_dir}" volumes
fi' \
  "${HOME_VOLUME}:/backup-source/home" \
  "${DOCKER_VOLUME}:/backup-source/docker" \
  "${BACKUP_DIR}:/backup" \
  -- backup-helper "${PROFILE_NAME}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${BACKUP_BASENAME}" "${BACKUP_SCOPE}" \
  </dev/null; then
  dv::fail "backup helper failed."
fi

[[ -s "${BACKUP_FILE}" ]] || dv::fail "backup helper completed but did not create a non-empty archive."
SUCCESS=1
printf '✅ Created backup: %s\n' "${BACKUP_FILE}"
