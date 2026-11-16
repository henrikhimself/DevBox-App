#!/usr/bin/env bash
set -uo pipefail

# F54 - resuming a kept container keeps its original named workspace mount
# (workspace-path and -t are ignored on resume)

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

CONTAINER_NAME='devbox-tplanwskeep-keep'

dv::cleanup() {
  dv::container_rm "${CONTAINER_NAME}"
  dv::volume_rm devbox-tplanwskeep devbox-tplanwskeep-docker
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest
dv::make_tmpdir

dv::container_rm "${CONTAINER_NAME}" devbox-tplanwskeep
bash "${REPO_DIR}/init.sh" tplanwskeep >/dev/null 2>&1 || dv::fail "init.sh tplanwskeep failed"

WS_DIR="${TENV_TMPDIR}/my-project"
mkdir -p "${WS_DIR}"

# The mount pair (source<TAB>destination) that run.sh must produce.
EXPECTED_PAIR="${WS_DIR}"$'\t''/workspace/my-project'

# Step 1: create a kept container with the default (named) workspace mount.
# The busybox fixture exits immediately; the kept container (no --rm) then
# lingers stopped and keeps its mounts for inspection.
port="$(dv::free_port)"
out="$(DEVBOX_IMAGE=busybox:latest bash "${REPO_DIR}/run.sh" -k -p "${port}" -v tplanwskeep "${WS_DIR}" 2>&1)" \
  || dv::fail "run.sh -k failed: ${out}"
[[ "${out}" == *"Bind-mounting ${WS_DIR} → /workspace/my-project"* ]] \
  || dv::fail "expected named bind-mount announcement, got: ${out}"

# The container may still be exiting at this point; poll until it exists in
# any state (the kept container is never auto-removed).
for _ in $(seq 1 50); do
  dv::container_exists "${CONTAINER_NAME}" && break
  sleep 0.2
done
dv::container_exists "${CONTAINER_NAME}" \
  || dv::fail "expected kept container ${CONTAINER_NAME} to exist after run.sh -k"

# Step 2: verify the mount landed at the named target.
mounts="$(dv::container_mounts "${CONTAINER_NAME}")"
printf '%s\n' "${mounts}" | grep -Fxq -- "${EXPECTED_PAIR}" \
  || dv::fail "expected mount ${WS_DIR} -> /workspace/my-project, got: ${mounts}"

# Step 3: stop it, then resume with -k and no workspace; the original named
# mount must be kept as-is.
dv::container_stop "${CONTAINER_NAME}"
out="$(DEVBOX_IMAGE=busybox:latest bash "${REPO_DIR}/run.sh" -k -v tplanwskeep 2>&1)" \
  || dv::fail "run.sh -k resume failed: ${out}"
[[ "${out}" == *"Resuming the kept container"* ]] \
  || dv::fail "expected 'Resuming the kept container' in output, got: ${out}"
dv::container_stop "${CONTAINER_NAME}"
mounts="$(dv::container_mounts "${CONTAINER_NAME}")"
printf '%s\n' "${mounts}" | grep -Fxq -- "${EXPECTED_PAIR}" \
  || dv::fail "expected resume to keep mount ${WS_DIR} -> /workspace/my-project, got: ${mounts}"

printf 'PASS\n'
