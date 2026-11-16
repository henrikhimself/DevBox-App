#!/usr/bin/env bash
set -uo pipefail

# F31 - run fails clearly when the port pool is exhausted

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanpoolexhaustexisting
  dv::volume_rm devbox-tplanpoolexhaust devbox-tplanpoolexhaust-docker
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

# Initialize the profile so run.sh's initialized check passes and doesn't
# mask the pool-exhaustion check under test.
bash "${REPO_DIR}/init.sh" tplanpoolexhaust >/dev/null 2>&1 || dv::fail "init.sh tplanpoolexhaust failed"

# Step 1: a running fixture container occupying the pool's single port
dv::container_rm devbox-tplanpoolexhaustexisting
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanpoolexhaustexisting \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'

# Step 2: run against a pool narrowed to exactly that one (occupied) port;
# must dv::fail clearly instead of attempting a colliding container run.
out="$(DEVBOX_IMAGE=busybox:latest DEVBOX_PORT_POOL_START="${port}" DEVBOX_PORT_POOL_END="${port}" \
  bash "${REPO_DIR}/run.sh" -v tplanpoolexhaust "${TENV_TMPDIR}" 2>&1)" \
  && dv::fail "expected failure when the pool is exhausted" || true
[[ "${out}" == *"No available SSH host port in the pool ${port}-${port}"* ]] \
  || dv::fail "expected pool-exhaustion message in output, got: ${out}"

printf 'PASS\n'
