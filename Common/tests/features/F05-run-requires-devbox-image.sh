#!/usr/bin/env bash
set -uo pipefail

# F05 - run requires devbox image

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplanimage devbox-tplanimage-docker
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::make_tmpdir

# Step 1: initialize profile
bash "${REPO_DIR}/init.sh" tplanimage >/dev/null 2>&1 || dv::fail "init.sh tplanimage failed"

# Steps 2+3+4: run with a non-existent image — must dv::fail with "not found"
FAKE_IMAGE='localhost:5000/hj/devbox-does-not-exist:99999'
out="$(DEVBOX_IMAGE="${FAKE_IMAGE}" bash "${REPO_DIR}/run.sh" -v tplanimage "${TENV_TMPDIR}" 2>&1)" \
  && dv::fail "expected failure for missing image" || true
[[ "${out}" == *"not found"* ]] || dv::fail "expected 'not found' in output, got: ${out}"

printf 'PASS\n'
