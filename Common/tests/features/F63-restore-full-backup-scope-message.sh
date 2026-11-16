#!/usr/bin/env bash
# shellcheck disable=SC2312 # Command substitutions in failure diagnostics intentionally ignore their own status.
set -uo pipefail

# F63 - restore -y reports full-backup scope and restores successfully

F63_RUNTIME_DIR="$(mktemp -d /tmp/devboxtest-runtime-XXXXXX)"
CONTAINER_CMD="${F63_RUNTIME_DIR}/container"
touch "${CONTAINER_CMD}"
chmod 755 "${CONTAINER_CMD}"

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  rm -rf "${F63_RUNTIME_DIR}"
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

REPO_DIR="${TENV_FRONTEND_DIR}"
[[ -f "${REPO_DIR}/restore.sh" ]] || dv::fail "./restore.sh not found at ${REPO_DIR}"

dv::make_tmpdir
FAKE_BIN="${TENV_TMPDIR}/bin"
ARCHIVE_SOURCE="${TENV_TMPDIR}/archive-source"
LOG_FILE="${TENV_TMPDIR}/container.log"
BACKUP_FILE="${TENV_TMPDIR}/profile-full.tar.gz"
mkdir -p "${FAKE_BIN}" "${ARCHIVE_SOURCE}/home" "${ARCHIVE_SOURCE}/docker/image"
printf 'home data\n' > "${ARCHIVE_SOURCE}/home/example"
printf 'image data\n' > "${ARCHIVE_SOURCE}/docker/image/example"
printf 'format=devbox-profile-backup-v1\nprofile=source\ncreated_utc=2026-01-01T00:00:00Z\nscope=full\n' > "${ARCHIVE_SOURCE}/manifest"
tar -C "${ARCHIVE_SOURCE}" -czf "${BACKUP_FILE}" manifest home docker

cat > "${FAKE_BIN}/container" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_CONTAINER_LOG:?}"
case "${1:-}" in
  system) printf 'status running\n' ;;
  inspect) exit 1 ;;
  volume)
    case "${2:-}" in
      inspect) exit 1 ;;
      create|rm) exit 0 ;;
    esac
    ;;
  image)
    case "${2:-}" in
      inspect) exit 0 ;;
    esac
    ;;
  run|delete) exit 0 ;;
esac
EOF
chmod 755 "${FAKE_BIN}/container"

out="$(FAKE_CONTAINER_LOG="${LOG_FILE}" CONTAINER_CMD="${FAKE_BIN}/container" \
  DEVBOX_IMAGE=busybox:latest \
  bash "${REPO_DIR}/restore.sh" -y tplanrestorefull "${BACKUP_FILE}" 2>&1)" \
  || dv::fail "restore.sh -y failed: ${out}"

[[ "${out}" == *"Backup scope: full backup: restore /home plus the full /data/docker tree."* ]] \
  || dv::fail "restore did not report the full backup scope: ${out}"
[[ "${out}" == *"Restored backup into profile tplanrestorefull"* ]] \
  || dv::fail "restore did not report success: ${out}"
grep -qxF 'volume create devbox-tplanrestorefull' "${LOG_FILE}" \
  || dv::fail "restore did not create the home volume: $(cat "${LOG_FILE}")"
grep -qxF 'volume create devbox-tplanrestorefull-docker' "${LOG_FILE}" \
  || dv::fail "restore did not create the Docker volume: $(cat "${LOG_FILE}")"

printf 'PASS\n'
