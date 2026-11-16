#!/usr/bin/env bash
set -uo pipefail

# F08 - stop with profile selection

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanvsel
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/stop.sh" ]] || dv::fail "./stop.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest

# Step 1: start container for test profile
dv::container_rm devbox-tplanvsel
dv::container_run_detached --name devbox-tplanvsel busybox:latest sh -c 'sleep 600'

# Step 2: stop selected profile
bash "${REPO_DIR}/stop.sh" -v tplanvsel >/dev/null 2>&1 || dv::fail "stop.sh -v tplanvsel failed"

# Step 3: verify container is gone
dv::container_is_running devbox-tplanvsel \
  && dv::fail "devbox-tplanvsel still running after stop.sh -v" || true

printf 'PASS\n'
