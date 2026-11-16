#!/usr/bin/env bash
set -uo pipefail

# F29 - run auto-selects a pool port for a new ephemeral profile

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanpoolauto
  dv::volume_rm devbox-tplanpoolauto devbox-tplanpoolauto-docker
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

# Step 1: initialize the profile and ensure no stale container exists
bash "${REPO_DIR}/init.sh" tplanpoolauto >/dev/null 2>&1 || dv::fail "init.sh tplanpoolauto failed"
dv::container_rm devbox-tplanpoolauto

# Step 2: run without -p; must succeed, auto-selecting a port from the
# default pool (55000-59000) and announcing it
out="$(DEVBOX_IMAGE=busybox:latest bash "${REPO_DIR}/run.sh" -v tplanpoolauto "${TENV_TMPDIR}" 2>&1)" \
  || dv::fail "run.sh failed: ${out}"
[[ "${out}" == *"auto-selected host port"* ]] \
  || dv::fail "expected auto-selection message in output, got: ${out}"

port="$(printf '%s\n' "${out}" | grep -oE 'auto-selected host port [0-9]+' | grep -oE '[0-9]+')"
[[ -n "${port}" ]] || dv::fail "could not extract auto-selected port from output: ${out}"
(( port >= 55000 && port <= 59000 )) \
  || dv::fail "expected auto-selected port in 55000-59000, got: ${port}"

printf 'PASS\n'
