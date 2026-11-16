#!/usr/bin/env bash
set -uo pipefail

# F04 - run requires initialized profile

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplannoninit devbox-tplannoninit-docker
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::make_tmpdir

# Use a fixture image known to be present so run.sh's image-existence check
# passes and doesn't mask the profile-initialized check under test (the
# initialized check now runs first, but keeping a valid image here still
# isolates this test to exactly the one failure mode it's checking).
dv::ensure_image busybox:latest

# Step 1: ensure profile volumes are absent
dv::volume_rm devbox-tplannoninit devbox-tplannoninit-docker

# Steps 2+3: run without initializing — must dv::fail with "has not been initialized"
out="$(DEVBOX_IMAGE=busybox:latest bash "${REPO_DIR}/run.sh" -v tplannoninit "${TENV_TMPDIR}" 2>&1)" \
  && dv::fail "expected failure for non-initialized profile" || true
[[ "${out}" == *"has not been initialized"* ]] || dv::fail "expected 'has not been initialized' in output, got: ${out}"

printf 'PASS\n'
