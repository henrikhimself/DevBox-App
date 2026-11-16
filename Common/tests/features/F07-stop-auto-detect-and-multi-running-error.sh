#!/usr/bin/env bash
set -uo pipefail

# F07 - stop auto-detect and multi-running behavior
#
# Precondition: no devbox-* containers may be running when this test starts.

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanstop1 devbox-tplanstop2
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/stop.sh" ]] || dv::fail "./stop.sh not found at ${REPO_DIR}"
if dv::running_devbox_names | grep -q .; then
  printf '%s\n' '❌ Other devbox containers are already running on this host.'
  printf '%s\n' 'F07 tests host-wide auto-detect/multi-running behavior and requires a clean state.'
  printf '%s\n' 'Stop each running devbox first (./stop.sh -v <profile-name> for each one shown below), then retry.'
  dv::running_devbox_names >&2
  exit 1
fi

dv::ensure_image busybox:latest

# Step 1: start exactly one devbox container
dv::container_rm devbox-tplanstop1 devbox-tplanstop2
dv::container_run_detached --name devbox-tplanstop1 busybox:latest sh -c 'sleep 600'

# Step 2: stop.sh auto-detects and stops it
bash "${REPO_DIR}/stop.sh" >/dev/null 2>&1 || dv::fail "stop.sh failed to auto-stop single running devbox"
dv::container_is_running devbox-tplanstop1 \
  && dv::fail "devbox-tplanstop1 still running after stop.sh" || true
# Remove the stopped container before re-using the name in step 3
dv::container_rm devbox-tplanstop1

# Step 3: start two devbox containers
dv::container_run_detached --name devbox-tplanstop1 busybox:latest sh -c 'sleep 600'
dv::container_run_detached --name devbox-tplanstop2 busybox:latest sh -c 'sleep 600'

# Step 4: stop.sh must error when multiple are running
out="$(bash "${REPO_DIR}/stop.sh" 2>&1)" && dv::fail "expected failure for multiple running devboxes" || true
[[ "${out}" == *"Multiple devbox containers found"* ]] \
  || dv::fail "expected 'Multiple devbox containers found' in output, got: ${out}"

printf 'PASS\n'
