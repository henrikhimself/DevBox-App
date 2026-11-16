#!/usr/bin/env bash
set -uo pipefail

# F32 - forward requires a port argument

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# Step 1: no -p given at all
out="$(bash "${REPO_DIR}/forward.sh" 2>&1)" && dv::fail "expected failure when -p is omitted" || true
[[ "${out}" == *"-p host-port[:container-port] is required"* ]] \
  || dv::fail "expected -p requirement message, got: ${out}"

printf 'PASS\n'
