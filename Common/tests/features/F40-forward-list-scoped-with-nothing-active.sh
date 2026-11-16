#!/usr/bin/env bash
set -uo pipefail

# F40 - forward -l -v reports no active forwards for a profile with none

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# Step 1: -l -v for a profile that has never had a forward must report that
# clearly and succeed, without requiring its container to be running.
out="$(bash "${REPO_DIR}/forward.sh" -l -v tplanfwdlistnone 2>&1)" || dv::fail "forward.sh -l -v failed: ${out}"
[[ "${out}" == *"No active port forwards for profile 'tplanfwdlistnone'."* ]] \
  || dv::fail "expected 'No active port forwards for profile' message, got: ${out}"

printf 'PASS\n'
