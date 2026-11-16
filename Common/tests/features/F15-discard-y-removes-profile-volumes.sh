#!/usr/bin/env bash
set -uo pipefail

# F15 - discard -y removes profile volumes

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplandiscardy devbox-tplandiscardy-docker
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/discard.sh" ]] || dv::fail "./discard.sh not found at ${REPO_DIR}"

# Step 1: ensure profile volumes exist
bash "${REPO_DIR}/init.sh" tplandiscardy >/dev/null 2>&1 || dv::fail "init.sh tplandiscardy failed"
dv::volume_exists devbox-tplandiscardy        || dv::fail "setup: volume devbox-tplandiscardy missing"
dv::volume_exists devbox-tplandiscardy-docker || dv::fail "setup: volume devbox-tplandiscardy-docker missing"

# Step 2: discard with -y
bash "${REPO_DIR}/discard.sh" -y tplandiscardy >/dev/null 2>&1 || dv::fail "discard.sh -y tplandiscardy failed"

# Step 3: verify both volumes are removed
dv::volume_exists devbox-tplandiscardy \
  && dv::fail "volume devbox-tplandiscardy still exists after discard" || true
dv::volume_exists devbox-tplandiscardy-docker \
  && dv::fail "volume devbox-tplandiscardy-docker still exists after discard" || true

printf 'PASS\n'
