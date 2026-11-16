#!/usr/bin/env bash
set -uo pipefail

# F17 - run requires workspace for first-time keep create

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplannewkeep-keep devbox-tplannewkeep
  dv::volume_rm devbox-tplannewkeep devbox-tplannewkeep-docker
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest

# Step 1: ensure no container exists yet for this profile, under either name
dv::container_rm devbox-tplannewkeep-keep devbox-tplannewkeep

# Initialize the profile so run.sh's initialized check passes and doesn't
# mask the workspace-required check under test.
bash "${REPO_DIR}/init.sh" tplannewkeep >/dev/null 2>&1 || dv::fail "init.sh tplannewkeep failed"

# Step 2: -k with no workspace arg and no existing kept container must fail.
# Use a fixture image known to be present so run.sh's image-existence check
# passes and doesn't mask the workspace-required check under test.
out="$(DEVBOX_IMAGE=busybox:latest bash "${REPO_DIR}/run.sh" -k -v tplannewkeep 2>&1)" \
  && dv::fail "expected failure when no workspace given and no kept container exists" || true
[[ "${out}" == *"workspace-path is required"* ]] \
  || dv::fail "expected 'workspace-path is required' in output, got: ${out}"

printf 'PASS\n'
