#!/usr/bin/env bash
set -uo pipefail

# F30 - run auto-select avoids a port already used by another devbox profile

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanpoolavoid devbox-tplanpoolavoidexisting
  dv::volume_rm devbox-tplanpoolavoid devbox-tplanpoolavoid-docker
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

# Step 1: a running fixture container occupying the first port of a
# narrow, deterministic 2-port pool
dv::container_rm devbox-tplanpoolavoidexisting
pool_start="$(dv::free_port)"
pool_end="$(( pool_start + 1 ))"
dv::container_run_detached \
  --name devbox-tplanpoolavoidexisting \
  -p "${pool_start}:2222" \
  busybox:latest sh -c 'sleep 600'

# Step 2: initialize the profile under test
bash "${REPO_DIR}/init.sh" tplanpoolavoid >/dev/null 2>&1 || dv::fail "init.sh tplanpoolavoid failed"
dv::container_rm devbox-tplanpoolavoid

# Step 3: run without -p against the narrowed pool; must skip the occupied
# first port and pick the second one instead
out="$(DEVBOX_IMAGE=busybox:latest DEVBOX_PORT_POOL_START="${pool_start}" DEVBOX_PORT_POOL_END="${pool_end}" \
  bash "${REPO_DIR}/run.sh" -v tplanpoolavoid "${TENV_TMPDIR}" 2>&1)" || dv::fail "run.sh failed: ${out}"
[[ "${out}" == *"auto-selected host port ${pool_end} "* ]] \
  || dv::fail "expected auto-selected port ${pool_end} (skipping occupied ${pool_start}) in output, got: ${out}"

printf 'PASS\n'
