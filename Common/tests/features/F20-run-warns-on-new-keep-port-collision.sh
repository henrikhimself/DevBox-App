#!/usr/bin/env bash
set -uo pipefail

# F20 - run warns (but succeeds) on new keep creation with a colliding port

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanportwarnexisting-keep devbox-tplanportwarnnew-keep
  dv::volume_rm devbox-tplanportwarnnew devbox-tplanportwarnnew-docker
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

# Step 1: an existing stopped kept container simulating another profile
# already using a given port
dv::container_rm devbox-tplanportwarnexisting-keep
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanportwarnexisting-keep \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'
dv::container_stop devbox-tplanportwarnexisting-keep

# Step 2: initialize a brand-new profile and ensure no stale container exists
bash "${REPO_DIR}/init.sh" tplanportwarnnew >/dev/null 2>&1 || dv::fail "init.sh tplanportwarnnew failed"
dv::container_rm devbox-tplanportwarnnew-keep

# Step 3: creating a new kept container on the same (colliding) port must
# succeed, but warn
out="$(DEVBOX_IMAGE=busybox:latest bash "${REPO_DIR}/run.sh" -k -v tplanportwarnnew -p "${port}" "${TENV_TMPDIR}" 2>&1)" \
  || dv::fail "expected success (warning only) but run.sh failed: ${out}"
[[ "${out}" == *"port ${port} is already used by devbox profile 'tplanportwarnexisting'"* ]] \
  || dv::fail "expected port-collision warning naming 'tplanportwarnexisting' in output, got: ${out}"

printf 'PASS\n'
