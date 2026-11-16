#!/usr/bin/env bash
set -uo pipefail

# F19 - run resume blocked by port conflict with a running profile

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanportblockother devbox-tplanportblock-keep
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest

# Step 1: create the stopped kept container for the profile under test,
# configured with a free port. It's started briefly then stopped, so the
# port is free again before the "other profile" fixture below binds it —
# both fixtures must never be bound to the same port at the same time
# during setup, or setup itself would hit a real port conflict.
dv::container_rm devbox-tplanportblock-keep
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanportblock-keep \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'
dv::container_stop devbox-tplanportblock-keep

# Step 2: a running "other profile" container now takes over that same port
dv::container_rm devbox-tplanportblockother
dv::container_run_detached \
  --name devbox-tplanportblockother \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'

# Step 3: resuming the kept container must be blocked by the port conflict
out="$(bash "${REPO_DIR}/run.sh" -k -v tplanportblock 2>&1)" \
  && dv::fail "expected failure when resume port conflicts with a running profile" || true
[[ "${out}" == *"port ${port} is already in use by running profile 'tplanportblockother'"* ]] \
  || dv::fail "expected port-conflict message naming 'tplanportblockother' in output, got: ${out}"

printf 'PASS\n'
