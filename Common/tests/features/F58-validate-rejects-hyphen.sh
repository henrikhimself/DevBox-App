#!/usr/bin/env bash
set -uo pipefail

# F58 - validate rejects hyphen in names

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplanunderscored devbox-tplanunderscored-docker
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/ssh.sh" ]] || dv::fail "./ssh.sh not found at ${REPO_DIR}"

# Step 1: init.sh rejects a hyphenated profile name (hyphens are banned so
# profile names never collide with the internal 'devbox-<profile>' /
# 'devbox-<profile>-keep' container naming).
out1="$(bash "${REPO_DIR}/init.sh" 'bad-name' 2>&1)" && dv::fail "expected failure for hyphenated profile name but got success" || true
[[ "${out1}" == *"must start with an alphanumeric"* ]] \
  || dv::fail "expected the profile-name validation message in output, got: ${out1}"
[[ "${out1}" == *"hyphens are not allowed"* ]] \
  || dv::fail "expected the hyphen-specific validation hint in output, got: ${out1}"

# Step 2: ssh.sh rejects a hyphenated tmux session name (same character rule).
out2="$(bash "${REPO_DIR}/ssh.sh" -s 'bad-session' 2>&1)" && dv::fail "expected failure for hyphenated session name but got success" || true
[[ "${out2}" == *"session-name must start with an alphanumeric"* ]] \
  || dv::fail "expected the session-name validation message in output, got: ${out2}"
[[ "${out2}" == *"hyphens are not allowed"* ]] \
  || dv::fail "expected the hyphen-specific validation hint in output, got: ${out2}"

# Step 3: underscored names remain valid (regression guard for the new
# character set).
bash "${REPO_DIR}/init.sh" tplanunderscored >/dev/null 2>&1 \
  || dv::fail "expected success for underscored profile name"

printf 'PASS\n'
