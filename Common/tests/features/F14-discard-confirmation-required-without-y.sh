#!/usr/bin/env bash
set -uo pipefail

# F14 - discard confirmation required without -y

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplandiscardask devbox-tplandiscardask-docker
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/discard.sh" ]] || dv::fail "./discard.sh not found at ${REPO_DIR}"

# Step 1: ensure profile volumes exist
bash "${REPO_DIR}/init.sh" tplandiscardask >/dev/null 2>&1 || dv::fail "init.sh tplandiscardask failed"

# Step 2+3: run without -y in non-interactive mode (stdin redirected from /dev/null)
out="$(bash "${REPO_DIR}/discard.sh" tplandiscardask </dev/null 2>&1)" \
  && dv::fail "expected failure when stdin is not a tty and -y is omitted" || true
[[ "${out}" == *"Re-run with -y"* ]] \
  || dv::fail "expected 'Re-run with -y' in output, got: ${out}"

printf 'PASS\n'
