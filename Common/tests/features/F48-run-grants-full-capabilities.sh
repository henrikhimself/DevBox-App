#!/usr/bin/env bash
set -uo pipefail

# F48 - run grants the full capability set (--cap-add ALL); Apple Container only
# (Docker launches with --privileged: see F66)

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplancaps devbox-tplancaps-docker
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
  bash "${REPO_DIR}/init.sh" tplancaps >/dev/null 2>&1 || dv::fail "init.sh tplancaps failed"

# Clear the log so it only captures the run.sh invocation.
: > "${LOG_FILE}"

# Step 2: run a plain ephemeral devbox; must succeed.
if ! out="$(FAKE_CONTAINER_LOG="${LOG_FILE}" \
  DEVBOX_IMAGE=busybox:latest PATH="${FAKE_BIN}:${PATH}" \
  bash "${REPO_DIR}/run.sh" -p 2223 -v tplancaps "${TENV_TMPDIR}" 2>&1)"; then
  dv::fail "run.sh failed: ${out}"
fi

# Step 3: assert the full capability set is granted.
container_log="$(cat "${LOG_FILE}")"
grep -Fq -- "--cap-add ALL" "${LOG_FILE}" \
  || dv::fail "expected --cap-add ALL in container run args, got: ${container_log}"

# Step 4: assert the Docker Engine posture flags are absent from the
# 'container run' invocation (Apple Container uses --cap-add ALL instead).
run_line="$(dv::logged_run_line "${LOG_FILE}")"
[[ -n "${run_line}" ]] || dv::fail "no 'container run' invocation captured, log: ${container_log}"
if grep -Fq -- '--privileged' <<<"${run_line}"; then
  dv::fail "container run must not use --privileged, got: ${run_line}"
fi
if grep -Fq -- '--group-add' <<<"${run_line}"; then
  dv::fail "container run must not use --group-add, got: ${run_line}"
fi
if grep -Fq -- '/var/run/docker.sock' <<<"${run_line}"; then
  dv::fail "container run must not mount the host Docker socket, got: ${run_line}"
fi

# Step 5: Apple posture: no Docker device/security options.
for foreign in '--device' '--security-opt'; do
  if grep -Fq -- "${foreign}" <<<"${run_line}"; then dv::fail "apple run must not contain ${foreign}, got: ${run_line}"; fi
done

printf 'PASS\n'
