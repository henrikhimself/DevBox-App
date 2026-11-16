#!/usr/bin/env bash
set -uo pipefail

# F09 - stop force-remove kept container

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplankeeprm-keep
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/stop.sh" ]] || dv::fail "./stop.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest

# Step 1: create stopped kept container
dv::container_rm devbox-tplankeeprm-keep
dv::container_create devbox-tplankeeprm-keep busybox:latest sh || dv::fail "setup: dv::container_create devbox-tplankeeprm-keep failed"

# Step 2: force-remove via stop.sh -D -v
bash "${REPO_DIR}/stop.sh" -D -v tplankeeprm >/dev/null 2>&1 || dv::fail "stop.sh -D -v tplankeeprm failed"

# Step 3: verify container no longer exists
dv::container_exists devbox-tplankeeprm-keep \
  && dv::fail "devbox-tplankeeprm-keep still exists after -D removal" || true

printf 'PASS\n'
