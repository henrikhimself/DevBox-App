#!/usr/bin/env bash
set -uo pipefail

# F27 - ssh warns when ~/.ssh/config doesn't Include devbox_config

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplansshinc
  dv::cleanup_fake_home
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/ssh.sh" ]] || dv::fail "./ssh.sh not found at ${REPO_DIR}"

# Safety: confirm the real ~/.ssh/devbox_config (this test process's own
# actual HOME, never overridden below) is untouched by this test.
REAL_DEVBOX_CONFIG="${HOME}/.ssh/devbox_config"
BEFORE_HASH=''
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  BEFORE_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
fi

dv::ensure_image busybox:latest

# Step 1: a running fixture container for the profile under test
dv::container_rm devbox-tplansshinc
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplansshinc \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'

# Step 2: a scratch HOME with no ~/.ssh/config at all
dv::make_fake_home

# Step 3: fake 'ssh' shim so the command succeeds without a real ssh session
FAKE_BIN_DIR="$(mktemp -d)"
SSH_SHIM_LOG="$(mktemp)"
cat > "${FAKE_BIN_DIR}/ssh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SSH_SHIM_LOG:?}"
SHIM
chmod +x "${FAKE_BIN_DIR}/ssh"

# Step 4: run ssh.sh; must succeed but warn about the missing Include
out="$(PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" SSH_SHIM_LOG="${SSH_SHIM_LOG}" \
  bash "${REPO_DIR}/ssh.sh" -v tplansshinc 2>&1)" || dv::fail "expected success (warning only) but ssh.sh failed: ${out}"
[[ "${out}" == *"doesn't appear to Include ~/.ssh/devbox_config"* ]] \
  || dv::fail "expected the missing-Include warning in output, got: ${out}"
[[ "${out}" == *"Include ~/.ssh/devbox_config"* ]] \
  || dv::fail "expected the suggested Include line in output, got: ${out}"

# Verify the real ~/.ssh/devbox_config was never touched
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  AFTER_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
  [[ "${BEFORE_HASH}" == "${AFTER_HASH}" ]] || dv::fail "real ~/.ssh/devbox_config was modified!"
elif [[ -n "${BEFORE_HASH}" ]]; then
  dv::fail "real ~/.ssh/devbox_config existed before but is now missing!"
fi

printf 'PASS\n'
