#!/usr/bin/env bash
set -uo pipefail

# F38 - forward -D (no -p, no -v) errors clearly when no forwards are active anywhere

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${DEVBOX_FRONTEND_DIR:?DEVBOX_FRONTEND_DIR not set; run through the frontend tests/run-tests.sh}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

# This test depends on a host-wide "no active forwards anywhere" state
# (unlike other forward.sh tests, which use a unique-per-test profile name
# to avoid collisions), so guard against leftover forwards from outside
# this test run causing a false failure.
SOCKET_DIR="/tmp/devbox-forwards-$(id -u)"
if [[ -d "${SOCKET_DIR}" ]] && find "${SOCKET_DIR}" -name '*.sock' -type s 2>/dev/null | grep -q .; then
  printf '%s\n' '❌ Pre-existing forward sockets found; this test requires a clean state.' >&2
  printf '%s\n' "Close them first (e.g. ./forward.sh -D -y), then retry." >&2
  exit 1
fi

# Step 1: -D with no -p and no -v, when no forwards are active anywhere,
# must dv::fail clearly.
out="$(bash "${REPO_DIR}/forward.sh" -D 2>&1)" \
  && dv::fail "expected failure when no forwards are active anywhere" || true
[[ "${out}" == *"No active forwards found."* ]] \
  || dv::fail "expected 'No active forwards found.' message, got: ${out}"

printf 'PASS\n'
