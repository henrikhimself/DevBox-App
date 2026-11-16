#!/usr/bin/env bash
set -uo pipefail

# F26 - ssh writes the SSH block correctly and invokes ssh with the
# right arguments (tmux create-or-attach remote command, default and -s)

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanssh
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
dv::container_rm devbox-tplanssh
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanssh \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'

dv::make_fake_home

# Step 2: pre-seed devbox_config with unrelated blocks that must survive
# untouched (proves no cross-match, no collateral damage to other profiles)
mkdir -p "${TENV_FAKE_HOME}/.ssh"
cat > "${TENV_FAKE_HOME}/.ssh/devbox_config" <<'EOF'
Host devbox-other
  HostName localhost
  Port 12345
  User bob
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host devbox-tplanssh2
  HostName localhost
  Port 22222
  User bob
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF

# Step 3: fake 'ssh' shim to capture invocation arguments (ssh.sh execs
# into it, so the shim's own exit becomes ssh.sh's exit)
FAKE_BIN_DIR="$(mktemp -d)"
SSH_SHIM_LOG="$(mktemp)"
cat > "${FAKE_BIN_DIR}/ssh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SSH_SHIM_LOG:?}"
SHIM
chmod +x "${FAKE_BIN_DIR}/ssh"

dv::run_ssh() {
  PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" SSH_SHIM_LOG="${SSH_SHIM_LOG}" \
    bash "${REPO_DIR}/ssh.sh" -v tplanssh
}

out="$(dv::run_ssh 2>&1)" || dv::fail "ssh.sh failed: ${out}"

# Step 3b: -s selects the named extra session of the same profile
dv::run_ssh_s() {
  PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" SSH_SHIM_LOG="${SSH_SHIM_LOG}" \
    bash "${REPO_DIR}/ssh.sh" -v tplanssh -s lint
}
out="$(dv::run_ssh_s 2>&1)" || dv::fail "ssh.sh -s lint failed: ${out}"
ARG2_S="$(sed -n '3p' "${SSH_SHIM_LOG}")"
[[ "${ARG2_S}" == "tmux -u new-session -A -s 'devbox-tplanssh:lint' -c '/workspace' bash -l" ]] \
  || dv::fail "arg2 (-s) mismatch: ${ARG2_S}"

# Step 4: assert ssh was invoked with exactly the right arguments
# (the -s run above overwrote the log, so re-run the default invocation)
out="$(dv::run_ssh 2>&1)" || dv::fail "re-run of ssh.sh failed: ${out}"
LOGGED_LINE_COUNT="$(wc -l < "${SSH_SHIM_LOG}" | tr -d ' ')"
LOGGED_CONTENT="$(cat "${SSH_SHIM_LOG}")"
ARG0="$(sed -n '1p' "${SSH_SHIM_LOG}")"
ARG1="$(sed -n '2p' "${SSH_SHIM_LOG}")"
ARG2="$(sed -n '3p' "${SSH_SHIM_LOG}")"
[[ "${LOGGED_LINE_COUNT}" -eq 3 ]] \
  || dv::fail "expected 3 args logged to ssh, got ${LOGGED_LINE_COUNT}: ${LOGGED_CONTENT}"
[[ "${ARG0}" == '-t' ]] || dv::fail "arg0 mismatch: ${ARG0}"
[[ "${ARG1}" == 'devbox-tplanssh' ]] || dv::fail "arg1 mismatch: ${ARG1}"
[[ "${ARG2}" == "tmux -u new-session -A -s 'devbox-tplanssh' -c '/workspace' bash -l" ]] \
  || dv::fail "arg2 mismatch: ${ARG2}"

# Step 5: assert permissions and block content
SSH_DIR_MATCH="$(find "${TENV_FAKE_HOME}/.ssh" -maxdepth 0 -perm 700 2>/dev/null)"
[[ -n "${SSH_DIR_MATCH}" ]] || dv::fail "expected ~/.ssh to be exactly 700"
CONFIG_FILE_MATCH="$(find "${TENV_FAKE_HOME}/.ssh/devbox_config" -maxdepth 0 -perm 600 2>/dev/null)"
[[ -n "${CONFIG_FILE_MATCH}" ]] || dv::fail "expected devbox_config to be exactly 600"
grep -qx "Host devbox-tplanssh" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected 'Host devbox-tplanssh' block in devbox_config"
grep -q "Port ${port}" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected 'Port ${port}' in devbox_config"

# Step 6: assert the unrelated pre-seeded blocks are untouched
grep -qx "Host devbox-other" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected pre-existing 'Host devbox-other' block to survive"
grep -qx "Host devbox-tplanssh2" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected pre-existing 'Host devbox-tplanssh2' block to survive"

FIRST_RUN_HASH="$(sha256sum "${TENV_FAKE_HOME}/.ssh/devbox_config" | awk '{print $1}')"

# Step 7: re-run twice more; content must be byte-identical each time
# (regression test for a blank-line-accumulation bug caught during design
# review, before it ever shipped — see F22)
for _ in 1 2; do
  out="$(dv::run_ssh 2>&1)" || dv::fail "re-run of ssh.sh failed: ${out}"
  REPEAT_HASH="$(sha256sum "${TENV_FAKE_HOME}/.ssh/devbox_config" | awk '{print $1}')"
  [[ "${REPEAT_HASH}" == "${FIRST_RUN_HASH}" ]] \
    || dv::fail "devbox_config changed on a repeat run with no configuration change"
done

# Verify the real ~/.ssh/devbox_config was never touched by any of the above
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  AFTER_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
  [[ "${BEFORE_HASH}" == "${AFTER_HASH}" ]] || dv::fail "real ~/.ssh/devbox_config was modified!"
elif [[ -n "${BEFORE_HASH}" ]]; then
  dv::fail "real ~/.ssh/devbox_config existed before but is now missing!"
fi

printf 'PASS\n'
