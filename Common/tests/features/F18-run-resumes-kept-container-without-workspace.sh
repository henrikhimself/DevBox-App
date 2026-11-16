#!/usr/bin/env bash
set -uo pipefail

# F18 - run resumes kept container without workspace argument

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanresume-keep
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest

# Step 1: create a stopped kept container
dv::container_rm devbox-tplanresume-keep
dv::container_create devbox-tplanresume-keep busybox:latest sh \
  || dv::fail "setup: dv::container_create devbox-tplanresume-keep failed"

# Step 2: -k with no workspace arg must resume the existing kept container
out="$(bash "${REPO_DIR}/run.sh" -k -v tplanresume 2>&1)" || dv::fail "run.sh failed to resume: ${out}"
[[ "${out}" == *"Resuming the kept container"* ]] \
  || dv::fail "expected 'Resuming the kept container' in output, got: ${out}"

printf 'PASS\n'
