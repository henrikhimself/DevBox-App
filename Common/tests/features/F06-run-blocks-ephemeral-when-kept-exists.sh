#!/usr/bin/env bash
set -uo pipefail

# F06 - run blocks ephemeral when kept container exists

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplankeep-keep
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest
dv::make_tmpdir

# Step 1: create a stopped kept container
dv::container_rm devbox-tplankeep-keep
dv::container_create devbox-tplankeep-keep busybox:latest sh || dv::fail "setup: dv::container_create devbox-tplankeep-keep failed"

# Steps 2+3: ephemeral run must be blocked
out="$(bash "${REPO_DIR}/run.sh" -v tplankeep "${TENV_TMPDIR}" 2>&1)" && dv::fail "expected failure when kept container exists" || true
[[ "${out}" == *"has a kept container"* ]] || dv::fail "expected 'has a kept container' in output, got: ${out}"

printf 'PASS\n'
