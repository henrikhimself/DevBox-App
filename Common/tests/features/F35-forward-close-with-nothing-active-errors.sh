#!/usr/bin/env bash
set -uo pipefail

# F35 - forward -D errors clearly when no forward is active for the profile

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# Step 1: -D for a profile/port with no active forward must dv::fail clearly,
# without requiring the profile's container to be running at all (a
# forward's lifecycle is independent of container state).
out="$(bash "${REPO_DIR}/forward.sh" -D -v tplanfwdnoneactive -p 54321:54321 2>&1)" \
  && dv::fail "expected failure when no forward is active" || true
[[ "${out}" == *"No active forward found for profile 'tplanfwdnoneactive' on 54321:54321"* ]] \
  || dv::fail "expected 'No active forward found' message, got: ${out}"

printf 'PASS\n'
