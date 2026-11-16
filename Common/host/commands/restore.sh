#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2310,SC2312 # Helper command is intentionally single-quoted; status functions are predicates.
# Restore a profile-volume archive created by backup.sh.
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/restore.sh,
# Docker/restore.sh), which has already sourced its shared.sh (adapter + libraries).

dv::usage() {
  cat <<'EOF'
Usage: restore.sh [-y] <profile-name> <backup.tar.gz>

Restores a backup created by ./backup.sh into a new, absent profile. The
profile must have no home/Docker volumes and no ephemeral or kept container.
The archive replaces neither an existing profile nor its workspace bind mount.

Options:
  -y  Skip the restore confirmation prompt
EOF
}

dv::fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
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

if [[ $# -ne 2 ]]; then
  dv::usage
  exit 1
fi

PROFILE_NAME="${1}"
BACKUP_INPUT="${2}"
DEVBOX_IMAGE="${DEVBOX_IMAGE:-${DEVBOX_DEFAULT_IMAGE}}"

dv::validate_profile_name "${PROFILE_NAME}"
dv::require_jq
dv::set_profile_volume_vars "${PROFILE_NAME}"

[[ "${BACKUP_INPUT}" == *.tar.gz ]] || dv::fail "backup path must end in .tar.gz: ${BACKUP_INPUT}"
[[ -f "${BACKUP_INPUT}" ]] || dv::fail "backup file does not exist: ${BACKUP_INPUT}"
[[ -r "${BACKUP_INPUT}" ]] || dv::fail "backup file is not readable: ${BACKUP_INPUT}"
command -v tar >/dev/null 2>&1 || dv::fail 'tar is required to validate the backup archive.'

BACKUP_DIR_INPUT="$(dirname -- "${BACKUP_INPUT}")"
BACKUP_DIR="$(cd "${BACKUP_DIR_INPUT}" && pwd -P)"
BACKUP_BASENAME="$(basename -- "${BACKUP_INPUT}")"
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_BASENAME}"

# Validate both the archive format and paths before creating any volumes.
manifest="$(tar -xOzf "${BACKUP_FILE}" manifest 2>/dev/null)" \
  || dv::fail "backup archive does not contain a readable manifest."
printf '%s\n' "${manifest}" | grep -qxF 'format=devbox-profile-backup-v1' \
  || dv::fail 'backup archive has an unsupported format.'
archive_scope_line="$(printf '%s\n' "${manifest}" | grep '^scope=' || true)"
case "${archive_scope_line}" in
  'scope=named-volumes')
    ARCHIVE_SCOPE='named-volumes'
    ARCHIVE_SCOPE_MESSAGE='default backup: restore /home plus Docker named volumes only'
    ;;
  'scope=full')
    ARCHIVE_SCOPE='full'
    ARCHIVE_SCOPE_MESSAGE='full backup: restore /home plus the full /data/docker tree'
    ;;
  '')
    dv::fail 'backup archive is missing the required scope metadata.'
    ;;
  *)
    dv::fail "backup archive has an unsupported scope: ${archive_scope_line#scope=}"
    ;;
esac
archive_paths="$(tar -tzf "${BACKUP_FILE}")" \
  || dv::fail 'backup archive is not a readable gzip-compressed tar file.'
printf '%s\n' "${archive_paths}" | grep -qxF 'home/' \
  || dv::fail 'backup archive is missing the home volume data.'
printf '%s\n' "${archive_paths}" | grep -qxF 'docker/' \
  || dv::fail 'backup archive is missing the Docker volume data.'
if [[ "${ARCHIVE_SCOPE}" == 'named-volumes' ]]; then
  printf '%s\n' "${archive_paths}" | grep -qxF 'docker/volumes/' \
    || dv::fail 'backup archive is missing the Docker named-volume data.'
fi
if printf '%s\n' "${archive_paths}" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
  dv::fail 'backup archive contains an unsafe path.'
fi

dv::ensure_container_backend_running

for container_name in "devbox-${PROFILE_NAME}" "devbox-${PROFILE_NAME}-keep"; do
  container_state="$(dv::container_status "${container_name}")"
  if [[ -n "${container_state}" ]]; then
    dv::fail "profile '${PROFILE_NAME}' already has a container (${container_name}). Discard it deliberately before restoring."
  fi
done

[[ "$(dv::volume_exists "${HOME_VOLUME}")" == '0' ]] \
  || dv::fail "profile '${PROFILE_NAME}' already has a home volume. Discard it deliberately before restoring."
[[ "$(dv::volume_exists "${DOCKER_VOLUME}")" == '0' ]] \
  || dv::fail "profile '${PROFILE_NAME}' already has a Docker volume. Discard it deliberately before restoring."
dv::image_exists "${DEVBOX_IMAGE}" \
  || dv::fail "image ${DEVBOX_IMAGE} not found. Build it first: make build"

printf 'ℹ️ Backup scope: %s.\n' "${ARCHIVE_SCOPE_MESSAGE}"
dv::confirm "Continue restoring profile '${PROFILE_NAME}' from ${BACKUP_FILE}?" "${ASSUME_YES}" || exit 1

HELPER_NAME="restore-${PROFILE_NAME}-$$"
VOLUMES_CREATED=0
SUCCESS=0
dv::cleanup() {
  dv::remove_helper_quietly "${HELPER_NAME}"
  if [[ "${SUCCESS}" -eq 0 && "${VOLUMES_CREATED}" -eq 1 ]]; then
    dv::delete_volume_if_present "${HOME_VOLUME}" || true
    dv::delete_volume_if_present "${DOCKER_VOLUME}" || true
  fi
}
trap dv::cleanup EXIT

dv::volume_create "${HOME_VOLUME}"
dv::volume_create "${DOCKER_VOLUME}"
VOLUMES_CREATED=1

printf '📥 Restoring profile %q from %s...\n' "${PROFILE_NAME}" "${BACKUP_FILE}"
if ! output="$(dv::run_helper_container "${HELPER_NAME}" "${DEVBOX_IMAGE}" \
  'set -e
tar -xzf "/backup/$1" -C /restore' \
  "${HOME_VOLUME}:/restore/home" \
  "${DOCKER_VOLUME}:/restore/docker" \
  "${BACKUP_DIR}:/backup" \
  -- restore-helper "${BACKUP_BASENAME}" \
  2>&1)"; then
  printf '%s\n' "${output}" >&2
  dv::fail "restore helper failed."
fi

SUCCESS=1
printf '✅ Restored backup into profile %q. Start it with ./run.sh -v %q <workspace-path>.\n' \
  "${PROFILE_NAME}" "${PROFILE_NAME}"
