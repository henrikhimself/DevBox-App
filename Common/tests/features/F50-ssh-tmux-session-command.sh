#!/usr/bin/env bash
set -uo pipefail

# F50 - ssh lands in a fixed per-profile tmux session; -s selects a named
# session; the shared name rule rejects dots (and colons) in session names

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  rm -rf "${FAKE_BIN_DIR:-}"
  rm -f "${SSH_SHIM_LOG:-}"
  dv::container_rm devbox-tpltm
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
dv::container_rm devbox-tpltm
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tpltm \
  -p "${port}:2222" \
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

dv::run_ssh() {
  # $1+ are extra ssh.sh args
  PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" SSH_SHIM_LOG="${SSH_SHIM_LOG}" \
    bash "${REPO_DIR}/ssh.sh" -v tpltm "$@"
}

dv::remote_cmd() {
  sed -n '3p' "${SSH_SHIM_LOG}"
}

# Step 3: default invocation targets the fixed per-profile session
out="$(dv::run_ssh 2>&1)" || dv::fail "ssh.sh failed: ${out}"
rc="$(dv::remote_cmd)"
[[ "${rc}" == "tmux -u new-session -A -s 'devbox-tpltm' -c '/workspace' bash -l" ]] \
  || dv::fail "default remote command mismatch: ${rc}"
[[ "${out}" == *"tmux session 'devbox-tpltm'"* ]] \
  || dv::fail "expected connect message to name the tmux session, got: ${out}"

# Step 4: repeat runs target the same session (attach, not recreate)
out="$(dv::run_ssh 2>&1)" || dv::fail "ssh.sh re-run failed: ${out}"
rc="$(dv::remote_cmd)"
[[ "${rc}" == "tmux -u new-session -A -s 'devbox-tpltm' -c '/workspace' bash -l" ]] \
  || dv::fail "re-run remote command mismatch: ${rc}"

# Step 5: -s selects the named extra session of the same profile
out="$(dv::run_ssh -s build 2>&1)" || dv::fail "ssh.sh -s build failed: ${out}"
rc="$(dv::remote_cmd)"
[[ "${rc}" == "tmux -u new-session -A -s 'devbox-tpltm:build' -c '/workspace' bash -l" ]] \
  || dv::fail "arg2 (-s) mismatch: ${rc}"

# Step 6: the shared name rule rejects '.' and ':' in session names
# (tmux forbids both; the tightened profile-name rule shares the class)
out="$(dv::run_ssh -s 'a.b' 2>&1)" && dv::fail "expected failure for dotted session name but got success" || true
[[ "${out}" == *"session-name must start with an alphanumeric character"* ]] \
  || dv::fail "expected session-name character-rule error, got: ${out}"
out="$(dv::run_ssh -s 'a:b' 2>&1)" && dv::fail "expected failure for colon session name but got success" || true
[[ "${out}" == *"session-name must start with an alphanumeric character"* ]] \
  || dv::fail "expected session-name character-rule error, got: ${out}"

# Step 7: the tightened profile-name rule rejects dots through the entry point
out="$(PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" SSH_SHIM_LOG="${SSH_SHIM_LOG}" \
  bash "${REPO_DIR}/ssh.sh" -v 'tpltm.keep' 2>&1)" && dv::fail "expected failure for dotted profile name but got success" || true
[[ "${out}" == *"profile-name must start with an alphanumeric character"* ]] \
  || dv::fail "expected profile-name character-rule error, got: ${out}"

# Verify the real ~/.ssh/devbox_config was never touched by any of the above
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  AFTER_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
  [[ "${BEFORE_HASH}" == "${AFTER_HASH}" ]] || dv::fail "real ~/.ssh/devbox_config was modified!"
elif [[ -n "${BEFORE_HASH}" ]]; then
  dv::fail "real ~/.ssh/devbox_config existed before but is now missing!"
fi

printf 'PASS\n'
