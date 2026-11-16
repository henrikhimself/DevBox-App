#!/usr/bin/env bash
set -uo pipefail

# F01 - init arg and profile validation

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"

# Step 1: no args should default to the 'home' profile
out1="$(bash "${REPO_DIR}/init.sh" 2>&1)" || dv::fail "expected success for no-args (default 'home') but got failure: ${out1}"
[[ "${out1}" == *"Initializing profile: home"* ]] \
  || dv::fail "expected no-args init to target the 'home' profile, got: ${out1}"
[[ "${out1}" == *"✅"* ]] || dv::fail "expected success marker in no-args init output, got: ${out1}"

# Step 2: more than one argument should dv::fail with usage
out3="$(bash "${REPO_DIR}/init.sh" alpha beta 2>&1)" && dv::fail "expected failure for extra args but got success" || true
[[ "${out3}" == *"Usage:"* ]] || dv::fail "expected 'Usage:' in extra-args output, got: ${out3}"

# Step 3: invalid profile name should dv::fail with validation error
out2="$(bash "${REPO_DIR}/init.sh" 'invalid*name' 2>&1)" && dv::fail "expected failure for invalid name but got success" || true
[[ "${out2}" == *"must start with an alphanumeric"* ]] \
  || dv::fail "expected the profile-name validation message in output, got: ${out2}"

printf 'PASS\n'
