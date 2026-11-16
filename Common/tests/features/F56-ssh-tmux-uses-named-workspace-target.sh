#!/usr/bin/env bash
set -uo pipefail

# F56 - ssh starts the tmux session in the named workspace target recorded by
# the devbox.workspace-target label (run.sh now writes /workspace/<project>
# for default runs)

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  rm -rf "${FAKE_BIN_DIR:-}"
  rm -f "${SSH_SHIM_LOG:-}"
  dv::container_rm devbox-tplanwsssh
  dv::cleanup_fake_home
  dv::cleanup_tmpdir
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
dv::make_tmpdir

WS_DIR="${TENV_TMPDIR}/my-project"
mkdir -p "${WS_DIR}"

# Step 1: a running fixture container exactly as run.sh now creates it for a
# default (no -t) run: label and mount at the named target.
dv::container_rm devbox-tplanwsssh
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanwsssh \
  --label "devbox.workspace-target=/workspace/my-project" \
  -p "${port}:2222" \
  -v "${WS_DIR}:/workspace/my-project" \
  busybox:latest sh -c 'sleep 600'

dv::make_fake_home
mkdir -p "${TENV_FAKE_HOME}/.ssh"

# Step 2: fake 'ssh' shim to capture invocation arguments (ssh.sh execs
# into it, so the shim's own exit becomes ssh.sh's exit)
FAKE_BIN_DIR="$(mktemp -d)"
SSH_SHIM_LOG="$(mktemp)"
cat > "${FAKE_BIN_DIR}/ssh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SSH_SHIM_LOG:?}"
SHIM
chmod +x "${FAKE_BIN_DIR}/ssh"

# Step 3: the tmux remote command must target the named workspace directory.
out="$(PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" SSH_SHIM_LOG="${SSH_SHIM_LOG}" \
  bash "${REPO_DIR}/ssh.sh" -v tplanwsssh 2>&1)" || dv::fail "ssh.sh failed: ${out}"
rc="$(sed -n '3p' "${SSH_SHIM_LOG}")"
[[ "${rc}" == "tmux -u new-session -A -s 'devbox-tplanwsssh' -c '/workspace/my-project' bash -l" ]] \
  || dv::fail "expected tmux session in /workspace/my-project, got: ${rc}"

# Verify the real ~/.ssh/devbox_config was never touched
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  AFTER_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
  [[ "${BEFORE_HASH}" == "${AFTER_HASH}" ]] || dv::fail "real ~/.ssh/devbox_config was modified!"
elif [[ -n "${BEFORE_HASH}" ]]; then
  dv::fail "real ~/.ssh/devbox_config existed before but is now missing!"
fi

printf 'PASS\n'
