#!/usr/bin/env bash
# shellcheck disable=SC2312 # Command substitutions in failure diagnostics intentionally ignore their own status.
set -uo pipefail

# F60 - backup archives the home volume plus Docker named volumes into one manifest archive

F60_RUNTIME_DIR="$(mktemp -d /tmp/devboxtest-runtime-XXXXXX)"
CONTAINER_CMD="${F60_RUNTIME_DIR}/container"
touch "${CONTAINER_CMD}"
chmod 755 "${CONTAINER_CMD}"

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  rm -rf "${F60_RUNTIME_DIR}"
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

REPO_DIR="${TENV_FRONTEND_DIR}"
[[ -f "${REPO_DIR}/backup.sh" ]] || dv::fail "./backup.sh not found at ${REPO_DIR}"

dv::make_tmpdir
ARCHIVE_SOURCE="${TENV_TMPDIR}/archive-source"
LOG_FILE="${TENV_TMPDIR}/container.log"
BACKUP_FILE="${TENV_TMPDIR}/profile.tar.gz"
mkdir -p "${ARCHIVE_SOURCE}/home" \
  "${ARCHIVE_SOURCE}/docker/volumes/demo/_data" \
  "${ARCHIVE_SOURCE}/docker/image"
printf 'home data\n' > "${ARCHIVE_SOURCE}/home/example"
printf 'named volume data\n' > "${ARCHIVE_SOURCE}/docker/volumes/demo/_data/example"
printf 'image data\n' > "${ARCHIVE_SOURCE}/docker/image/example"
printf 'format=devbox-profile-backup-v1\nprofile=tplanbackup\n' > "${ARCHIVE_SOURCE}/manifest"

# The stub models a stopped, initialized profile. Its helper-run response
# creates the archive that a real helper container would write through the
# /backup bind mount.
cat > "${CONTAINER_CMD}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_CONTAINER_LOG:?}"
case "${1:-}" in
  system) printf 'status running\n' ;;
  inspect) exit 1 ;;
  volume)
    case "${2:-}" in
      inspect) exit 0 ;;
    esac
    ;;
  image)
    case "${2:-}" in
      inspect) exit 0 ;;
    esac
    ;;
  run)
    if IFS= read -r -t 1 stdin_line; then
      printf 'stdin=%s\n' "${stdin_line}" >> "${FAKE_CONTAINER_LOG:?}"
    fi
    for arg in "$@"; do
      if [[ "${arg}" == *:/backup ]]; then
        backup_dir="${arg%:/backup}"
        printf '%s\n' 'helper archive progress' >&2
        tar -C "${FAKE_ARCHIVE_SOURCE:?}" -czf "${backup_dir}/${FAKE_ARCHIVE_NAME:?}" \
          manifest home docker/volumes
        exit 0
      fi
    done
    exit 1
    ;;
  delete) exit 0 ;;
esac
EOF
chmod 755 "${CONTAINER_CMD}"

out="$(printf '%s\n' 'must-not-reach-backup-helper' | \
  FAKE_CONTAINER_LOG="${LOG_FILE}" FAKE_ARCHIVE_SOURCE="${ARCHIVE_SOURCE}" \
  FAKE_ARCHIVE_NAME="$(basename "${BACKUP_FILE}")" \
  CONTAINER_CMD="${CONTAINER_CMD}" DEVBOX_IMAGE=busybox:latest \
  bash "${REPO_DIR}/backup.sh" tplanbackup "${BACKUP_FILE}" 2>&1)" \
  || dv::fail "backup.sh failed: ${out}"

[[ "${out}" == *'helper archive progress'* ]] \
  || dv::fail "backup.sh did not stream helper progress: ${out}"
! grep -Fq -- 'stdin=must-not-reach-backup-helper' "${LOG_FILE}" \
  || dv::fail "backup helper should run with standard input detached"
[[ -s "${BACKUP_FILE}" ]] || dv::fail "backup.sh did not create a non-empty archive"
manifest="$(tar -xOzf "${BACKUP_FILE}" manifest)" || dv::fail "archive manifest is unreadable"
[[ "${manifest}" == *'format=devbox-profile-backup-v1'* ]] \
  || dv::fail "archive manifest has no backup format marker: ${manifest}"
tar -tzf "${BACKUP_FILE}" | grep -qxF 'home/example' \
  || dv::fail "archive does not include home volume data"
tar -tzf "${BACKUP_FILE}" | grep -qxF 'docker/volumes/demo/_data/example' \
  || dv::fail "archive does not include Docker named volume data"
! tar -tzf "${BACKUP_FILE}" | grep -qxF 'docker/image/example' \
  || dv::fail "archive should exclude Docker image data"

grep -Fq -- '-v devbox-tplanbackup:/backup-source/home' "${LOG_FILE}" \
  || dv::fail "backup helper did not mount the home volume: $(cat "${LOG_FILE}")"
grep -Fq -- '-v devbox-tplanbackup-docker:/backup-source/docker' "${LOG_FILE}" \
  || dv::fail "backup helper did not mount the Docker volume: $(cat "${LOG_FILE}")"
grep -Fq -- "-v ${TENV_TMPDIR}:/backup" "${LOG_FILE}" \
  || dv::fail "backup helper did not bind-mount the output directory: $(cat "${LOG_FILE}")"
grep -Fq -- '--entrypoint /bin/bash' "${LOG_FILE}" \
  || dv::fail "backup helper did not override the DevBox /init entrypoint: $(cat "${LOG_FILE}")"
grep -Fq -- 'docker/volumes' "${LOG_FILE}" \
  || dv::fail "backup helper did not target Docker named volumes: $(cat "${LOG_FILE}")"
grep -Fq -- 'named-volumes' "${LOG_FILE}" \
  || dv::fail "backup helper did not pass the default backup scope: $(cat "${LOG_FILE}")"

printf 'PASS\n'
