#!/usr/bin/env bash
set -uo pipefail

# F53 - when the workspace path is the filesystem root (no usable basename),
# the mount falls back to /workspace/root

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplanwsroot devbox-tplanwsroot-docker
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::make_tmpdir
FAKE_BIN="${TENV_TMPDIR}/bin"
mkdir -p "${FAKE_BIN}"
LOG_FILE="${TENV_TMPDIR}/container.log"

# Runtime-appropriate stub CLI (see dv::install_run_stub): logs every invocation and
# mimics just enough of the CLI for run.sh and init.sh.
dv::install_run_stub "${FAKE_BIN}"

# Step 1: initialize the profile so run.sh's initialized-volumes check passes.
FAKE_CONTAINER_LOG="${LOG_FILE}" PATH="${FAKE_BIN}:${PATH}" \
  bash "${REPO_DIR}/init.sh" tplanwsroot >/dev/null 2>&1 || dv::fail "init.sh tplanwsroot failed"

# Clear the log so it only captures the run.sh invocation.
: > "${LOG_FILE}"

# Step 2: run with the filesystem root as the workspace; the fallback name
# 'root' must be used.
if ! out="$(FAKE_CONTAINER_LOG="${LOG_FILE}" \
  DEVBOX_IMAGE=busybox:latest PATH="${FAKE_BIN}:${PATH}" \
  bash "${REPO_DIR}/run.sh" -p 2223 -v tplanwsroot / 2>&1)"; then
  dv::fail "run.sh / failed: ${out}"
fi

# Step 3: assert the fallback destination and label.
container_log="$(cat "${LOG_FILE}")"
grep -Fq -- "-v /:/workspace/root" "${LOG_FILE}" \
  || dv::fail "expected workspace bind mount at /workspace/root in container run args, got: ${container_log}"
grep -Fq -- "--label devbox.workspace-target=/workspace/root" "${LOG_FILE}" \
  || dv::fail "expected workspace target label /workspace/root in container run args, got: ${container_log}"
[[ "${out}" == *"Bind-mounting / → /workspace/root"* ]] \
  || dv::fail "expected bind-mount announcement in output, got: ${out}"

printf 'PASS\n'
