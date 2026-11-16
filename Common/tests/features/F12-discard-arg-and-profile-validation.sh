#!/usr/bin/env bash
set -uo pipefail

# F12 - discard arg and profile validation

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/discard.sh" ]] || dv::fail "./discard.sh not found at ${REPO_DIR}"

# Step 1: no args must dv::fail with usage
out="$(bash "${REPO_DIR}/discard.sh" 2>&1)" && dv::fail "expected failure for no-args" || true
[[ "${out}" == *"Usage:"* ]] || dv::fail "expected 'Usage:' in no-args output, got: ${out}"

# Step 2: invalid profile name must dv::fail with validation error
out="$(bash "${REPO_DIR}/discard.sh" 'bad*name' 2>&1)" && dv::fail "expected failure for invalid profile name" || true
[[ "${out}" == *"must start with an alphanumeric"* ]] \
  || dv::fail "expected the profile-name validation message in output, got: ${out}"

printf 'PASS\n'
