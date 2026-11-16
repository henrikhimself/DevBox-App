#!/usr/bin/env bash
set -uo pipefail

# F37 - forward -D -v (no -p) errors clearly when no forwards are active for that profile

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# Step 1: -D -v with no -p, for a profile with no active forwards, must
# dv::fail clearly without requiring the profile's container to be running.
out="$(bash "${REPO_DIR}/forward.sh" -D -v tplanfwdbulknone 2>&1)" \
  && dv::fail "expected failure when no forwards are active for the profile" || true
[[ "${out}" == *"No active forwards found for profile 'tplanfwdbulknone'"* ]] \
  || dv::fail "expected 'No active forwards found for profile' message, got: ${out}"

printf 'PASS\n'
