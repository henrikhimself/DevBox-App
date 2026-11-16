#!/usr/bin/env bash
set -uo pipefail

# F33 - forward CLI port syntax validation

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# Step 1: non-numeric port
out="$(bash "${REPO_DIR}/forward.sh" -p abc 2>&1)" && dv::fail "expected failure for -p abc" || true
[[ "${out}" == *"Ports must be integers between 1 and 65535"* ]] \
  || dv::fail "expected port-format error, got: ${out}"

# Step 2: out-of-range port
out="$(bash "${REPO_DIR}/forward.sh" -p 70000 2>&1)" && dv::fail "expected failure for -p 70000" || true
[[ "${out}" == *"Ports must be integers between 1 and 65535"* ]] \
  || dv::fail "expected port-range error, got: ${out}"

# Step 3: host:container form with an invalid container-port
out="$(bash "${REPO_DIR}/forward.sh" -p 8443:notaport 2>&1)" && dv::fail "expected failure for -p 8443:notaport" || true
[[ "${out}" == *"Ports must be integers between 1 and 65535"* ]] \
  || dv::fail "expected port-format error for container-port, got: ${out}"

printf 'PASS\n'
