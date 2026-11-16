#!/usr/bin/env bash
set -uo pipefail

# F41 - forward -l is mutually exclusive with -p and -D

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# Step 1: -l combined with -p must dv::fail with usage, not attempt to list or
# start anything.
out="$(bash "${REPO_DIR}/forward.sh" -l -p 443 2>&1)" && dv::fail "expected failure when -l is combined with -p" || true
[[ "${out}" == *"Usage:"* ]] || dv::fail "expected 'Usage:' in output, got: ${out}"

# Step 2: -l combined with -D must also dv::fail with usage.
out="$(bash "${REPO_DIR}/forward.sh" -l -D 2>&1)" && dv::fail "expected failure when -l is combined with -D" || true
[[ "${out}" == *"Usage:"* ]] || dv::fail "expected 'Usage:' in output, got: ${out}"

printf 'PASS\n'
