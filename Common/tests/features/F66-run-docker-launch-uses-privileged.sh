#!/usr/bin/env bash
set -uo pipefail

# F66 - Docker run launches with --privileged --cap-add ALL (Docker Engine only)
# Apple counterpart: F48 (no --privileged)

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplanpriv devbox-tplanpriv-docker
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/run.sh" ]] || dv::fail "./run.sh not found at ${REPO_DIR}"

dv::make_tmpdir
FAKE_BIN="${TENV_TMPDIR}/bin"
mkdir -p "${FAKE_BIN}"
LOG_FILE="${TENV_TMPDIR}/container.log"

# Runtime-appropriate stub CLI (see dv::install_run_stub): logs every invocation and
# mimics just enough of the CLI for run.sh and init.sh.
dv::install_run_stub "${FAKE_BIN}"

# Step 1: initialize the profile so run.sh's initialized-volumes check passes.
FAKE_CONTAINER_LOG="${LOG_FILE}" PATH="${FAKE_BIN}:${PATH}" \
  bash "${REPO_DIR}/init.sh" tplanpriv >/dev/null 2>&1 || dv::fail "init.sh tplanpriv failed"

# Clear the log so it only captures the run.sh invocation.
: > "${LOG_FILE}"

# Step 2: run a plain ephemeral devbox; must succeed.
if ! out="$(FAKE_CONTAINER_LOG="${LOG_FILE}" \
  DEVBOX_IMAGE=busybox:latest PATH="${FAKE_BIN}:${PATH}" \
  bash "${REPO_DIR}/run.sh" -p 2223 -v tplanpriv "${TENV_TMPDIR}" 2>&1)"; then
  dv::fail "run.sh failed: ${out}"
fi

# Step 3: assert the exact approved Docker flag set.
run_line="$(dv::logged_run_line "${LOG_FILE}")"
[[ -n "${run_line}" ]] || dv::fail "no 'container run' invocation captured, log: $(cat "${LOG_FILE}")"
for want in '--privileged' '--cap-add ALL'; do
  grep -Fq -- " ${want} " <<<"${run_line} " || dv::fail "docker run must contain '${want}', got: ${run_line}"
done

# Step 4: nothing beyond the approved set: no explicit devices or security
# options (--privileged covers them), no host Docker socket, namespaces or
# Apple-only options.
for foreign in '--device' '--security-opt' '--group-add' '/var/run/docker.sock' '--pid' '--network' '--ipc' '--userns' '--sysctl' '--cap-drop' '--no-dns' '--tmpfs' '--hostname'; do
  if grep -Fq -- "${foreign}" <<<"${run_line}"; then dv::fail "docker run must not contain ${foreign}, got: ${run_line}"; fi
done

printf 'PASS\n'
