#!/usr/bin/env bash
set -uo pipefail

# F02 - init volume initialization idempotent

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplaninit devbox-tplaninit-docker
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"

# Step 1: first init
out1="$(bash "${REPO_DIR}/init.sh" tplaninit 2>&1)" || dv::fail "first init failed: ${out1}"
[[ "${out1}" == *"✅"* ]] || dv::fail "expected success marker in first init output, got: ${out1}"

# Step 2: verify volumes exist
dv::volume_exists devbox-tplaninit       || dv::fail "volume devbox-tplaninit not found after init"
dv::volume_exists devbox-tplaninit-docker || dv::fail "volume devbox-tplaninit-docker not found after init"

# Steps 3+4: second init (idempotent)
out2="$(bash "${REPO_DIR}/init.sh" tplaninit 2>&1)" || dv::fail "second init failed: ${out2}"
[[ "${out2}" == *"✅"* ]] || dv::fail "expected success marker in second init output, got: ${out2}"

printf 'PASS\n'
