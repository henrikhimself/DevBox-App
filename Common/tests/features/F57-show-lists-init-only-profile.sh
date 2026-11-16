#!/usr/bin/env bash
set -uo pipefail

# F57 - show lists init-only profile with status none

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplannone devbox-tplannone-docker
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/show.sh" ]] || dv::fail "./show.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"

# Step 1: initialize a profile without ever creating a container for it
dv::volume_rm devbox-tplannone devbox-tplannone-docker
bash "${REPO_DIR}/init.sh" tplannone >/dev/null 2>&1 \
  || dv::fail "init.sh tplannone failed"
dv::volume_exists devbox-tplannone \
  || dv::fail "setup: volume devbox-tplannone missing after init"

# Step 2: run show.sh
out="$(bash "${REPO_DIR}/show.sh" 2>&1)" || dv::fail "show.sh failed: ${out}"

# Step 3: header present
[[ "${out}" == *$'PROFILE\tSTATUS\tSSH_PORT\tEXISTING_WORKSPACE\tTARGET_PATH'* ]] \
  || dv::fail "expected column headers in output, got: ${out}"

# Step 4: the init-only profile is listed with status 'none' and '-' in the
# remaining columns (no container to inspect).
printf -v expected_row '%s\t%s\t%s\t%s\t%s' 'tplannone' 'none' '-' '-' '-'
[[ "${out}" == *"${expected_row}"* ]] \
  || dv::fail "expected row 'tplannone none - - -' in output, got: ${out}"

# Step 5: the profile disappears from show.sh once discarded. (On a clean
# host with no other profiles, show.sh exits 1 with the no-profiles message
# instead of printing a list - both are acceptable here.)
bash "${REPO_DIR}/discard.sh" -y tplannone >/dev/null 2>&1 \
  || dv::fail "discard.sh -y tplannone failed"
out="$(bash "${REPO_DIR}/show.sh" 2>&1)" || {
  [[ "${out}" == *"No devbox profiles found"* ]] \
    || dv::fail "show.sh failed after discard: ${out}"
}
if [[ "${out}" == *'tplannone'* ]]; then
  dv::fail "expected 'tplannone' to no longer appear after discard, got: ${out}"
fi

printf 'PASS\n'
