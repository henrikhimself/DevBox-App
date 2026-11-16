#!/usr/bin/env bash
set -uo pipefail

# F36 - forward -D without -v errors clearly when no profile has that forward active

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# Step 1: -D with no -v and no active forward anywhere on this port pair
# must dv::fail clearly, naming "any profile" since it couldn't auto-detect one.
out="$(bash "${REPO_DIR}/forward.sh" -D -p 54322:54322 2>&1)" \
  && dv::fail "expected failure when no forward is active for any profile" || true
[[ "${out}" == *"No active forward found on 54322:54322 for any profile"* ]] \
  || dv::fail "expected 'for any profile' message, got: ${out}"

printf 'PASS\n'
