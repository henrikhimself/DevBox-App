#!/usr/bin/env bash
set -uo pipefail

# F16 - show lists stopped container

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanstopped
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/show.sh" ]] || dv::fail "./show.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest
dv::make_tmpdir

# Step 1: start then stop a devbox-named container with a known mount
dv::container_rm devbox-tplanstopped
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanstopped \
  --label "devbox.workspace-target=${TENV_TMPDIR}" \
  -p "${port}:2222" \
  -v "${TENV_TMPDIR}:${TENV_TMPDIR}" \
  busybox:latest sh -c 'sleep 600'
dv::container_stop devbox-tplanstopped

# Sanity: the fixture itself must actually be stopped before trusting show.sh
dv::container_is_running devbox-tplanstopped \
  && dv::fail "setup: devbox-tplanstopped is still running after dv::container_stop"

# Step 2: run show.sh
out="$(bash "${REPO_DIR}/show.sh" 2>&1)" || dv::fail "show.sh failed: ${out}"

# Step 3: verify output contains header and expected row
[[ "${out}" == *$'PROFILE\tSTATUS\tSSH_PORT\tEXISTING_WORKSPACE\tTARGET_PATH'* ]] \
  || dv::fail "expected column headers in output, got: ${out}"
# dv::container_ssh_host_port reads configuration.publishedPorts (static
# creation-time config), which persists regardless of run state, so
# SSH_PORT resolves to the real configured port here, not '-'.
# Labels persist regardless of run state too, so the workspace target (and
# its mount source) still resolve exactly.
printf -v expected_row '%s\t%s\t%s\t%s\t%s' 'tplanstopped' 'stopped' "${port}" "${TENV_TMPDIR}" "${TENV_TMPDIR}"
[[ "${out}" == *"${expected_row}"* ]] \
  || dv::fail "expected row 'tplanstopped stopped ${port} ${TENV_TMPDIR} ${TENV_TMPDIR}' in output, got: ${out}"

printf 'PASS\n'
