#!/usr/bin/env bash
set -uo pipefail

# F11 - show lists profile and mount details

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanshow
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

# Step 1: start devbox-named container with known port and mount
dv::container_rm devbox-tplanshow
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanshow \
  --label "devbox.workspace-target=${TENV_TMPDIR}" \
  -p "${port}:2222" \
  -v "${TENV_TMPDIR}:${TENV_TMPDIR}" \
  busybox:latest sh -c 'sleep 600'

# Step 2: run show.sh
out="$(bash "${REPO_DIR}/show.sh" 2>&1)" || dv::fail "show.sh failed: ${out}"

# Step 3: verify output contains header and expected row
[[ "${out}" == *$'PROFILE\tSTATUS\tSSH_PORT\tEXISTING_WORKSPACE\tTARGET_PATH'* ]] \
  || dv::fail "expected column headers in output, got: ${out}"
# Build the expected row using variables (cannot embed variables in $'...' literals)
printf -v expected_row '%s\t%s\t%s\t%s\t%s' 'tplanshow' 'running' "${port}" "${TENV_TMPDIR}" "${TENV_TMPDIR}"
[[ "${out}" == *"${expected_row}"* ]] \
  || dv::fail "expected row 'tplanshow running ${port} ${TENV_TMPDIR} ${TENV_TMPDIR}' in output, got: ${out}"

printf 'PASS\n'
