#!/usr/bin/env bash
set -uo pipefail

# F13 - discard running container guard

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplandiscardrun
  dv::volume_rm devbox-tplandiscardrun devbox-tplandiscardrun-docker
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/discard.sh" ]] || dv::fail "./discard.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest

# Step 1: initialize profile
bash "${REPO_DIR}/init.sh" tplandiscardrun >/dev/null 2>&1 || dv::fail "init.sh tplandiscardrun failed"

# Step 2: start a running container for that profile
dv::container_rm devbox-tplandiscardrun
dv::container_run_detached --name devbox-tplandiscardrun busybox:latest sh -c 'sleep 600'

# Step 3+4: discard must dv::fail because container is running
out="$(bash "${REPO_DIR}/discard.sh" -y tplandiscardrun 2>&1)" && dv::fail "expected failure while container is running" || true
[[ "${out}" == *"has a running container"* ]] \
  || dv::fail "expected 'has a running container' in output, got: ${out}"

printf 'PASS\n'
