#!/usr/bin/env bash
set -uo pipefail

# F39 - forward -l reports no active forwards when there are none

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

# Step 1: -l with nothing active anywhere must report that clearly and
# succeed (this is the common steady state, not a failure).
out="$(bash "${REPO_DIR}/forward.sh" -l 2>&1)" || dv::fail "forward.sh -l failed: ${out}"
[[ "${out}" == *"No active port forwards."* ]] \
  || dv::fail "expected 'No active port forwards.' message, got: ${out}"

printf 'PASS\n'
