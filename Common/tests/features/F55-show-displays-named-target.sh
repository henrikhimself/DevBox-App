#!/usr/bin/env bash
set -uo pipefail

# F55 - show displays a named workspace target (/workspace/<project-name>) in
# the TARGET_PATH column, exactly as recorded by the devbox.workspace-target
# label that run.sh now writes for default runs

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanwsnamed
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/show.sh" ]] || dv::fail "./show.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest
dv::make_tmpdir

WS_DIR="${TENV_TMPDIR}/my-project"
mkdir -p "${WS_DIR}"

# Step 1: start a devbox-named fixture container exactly as run.sh now
# creates it for a default (no -t) run: label and mount at the named target.
dv::container_rm devbox-tplanwsnamed
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanwsnamed \
  --label "devbox.workspace-target=/workspace/my-project" \
  -p "${port}:2222" \
  -v "${WS_DIR}:/workspace/my-project" \
  busybox:latest sh -c 'sleep 600'

# Step 2: run show.sh and verify the named target appears in the row.
out="$(bash "${REPO_DIR}/show.sh" 2>&1)" || dv::fail "show.sh failed: ${out}"
printf -v expected_row '%s\t%s\t%s\t%s\t%s' 'tplanwsnamed' 'running' "${port}" "${WS_DIR}" '/workspace/my-project'
[[ "${out}" == *"${expected_row}"* ]] \
  || dv::fail "expected row 'tplanwsnamed running ${port} ${WS_DIR} /workspace/my-project' in output, got: ${out}"

printf 'PASS\n'
