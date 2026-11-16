#!/usr/bin/env bash
set -uo pipefail

# F21 - code requires a running profile

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::cleanup_fake_home
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/code.sh" ]] || dv::fail "./code.sh not found at ${REPO_DIR}"

# Safety: confirm the real ~/.ssh/devbox_config (this test process's own
# actual HOME, never overridden below) is untouched by this test.
REAL_DEVBOX_CONFIG="${HOME}/.ssh/devbox_config"
BEFORE_HASH=''
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  BEFORE_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
fi

dv::make_fake_home

# Step 1: no running container for a fresh profile name
out="$(HOME="${TENV_FAKE_HOME}" bash "${REPO_DIR}/code.sh" -v tplancodenorun 2>&1)" \
  && dv::fail "expected failure when no devbox is running for the profile" || true
[[ "${out}" == *"No running devbox for profile 'tplancodenorun'"* ]] \
  || dv::fail "expected 'No running devbox' message, got: ${out}"

# Verify the real ~/.ssh/devbox_config was never touched
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  AFTER_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
  [[ "${BEFORE_HASH}" == "${AFTER_HASH}" ]] || dv::fail "real ~/.ssh/devbox_config was modified!"
elif [[ -n "${BEFORE_HASH}" ]]; then
  dv::fail "real ~/.ssh/devbox_config existed before but is now missing!"
fi

printf 'PASS\n'
