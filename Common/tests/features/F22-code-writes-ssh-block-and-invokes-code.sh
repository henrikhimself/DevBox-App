#!/usr/bin/env bash
set -uo pipefail

# F22 - code writes the SSH block correctly and invokes code with the
# right arguments

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplancode
  dv::cleanup_fake_home
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/code.sh" ]] || dv::fail "./code.sh not found at ${REPO_DIR}"

# Safety: confirm the real ~/.ssh/devbox_config (this test process's own
# actual HOME, never overridden below) is untouched by this test.
REAL_DEVBOX_CONFIG="${HOME}/.ssh/devbox_config"
BEFORE_HASH=''
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  BEFORE_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
fi

dv::ensure_image busybox:latest

# Step 1: a running fixture container for the profile under test
dv::container_rm devbox-tplancode
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplancode \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'

dv::make_fake_home

# Step 2: 'code' not found in PATH must dv::fail clearly. A directory-inclusion
# PATH (e.g. adding the container runtime's, jq's, or even the repository
# scripts' own real directory) isn't safe here: on some setups 'code' is
# installed into that very same directory (e.g. a personal ~/bin holding
# both the repository scripts and a 'code' shim, or a vendor dir shared with
# jq/the runtime — all observed on macOS), which would defeat the test.
# Instead:
#   - Invoke code.sh by its already-resolved absolute path so its own
#     directory never needs to be in PATH at all.
#   - Symlink only the exact binaries code.sh needs internally (the
#     container runtime and jq; the runtime command is not exported, so code.sh's
#     own shared.sh re-detects the runtime under this narrowed PATH) into
#     an isolated scratch directory that provably contains nothing named
#     'code', regardless of where the real binaries happen to live.
# /usr/bin:/bin cover coreutils (mkdir, chmod, awk, etc.) that
# shared.sh/code.sh also need, and are OS-owned locations 'code' is never
# installed into.
SAFE_BIN_DIR="$(mktemp -d)"
RUNTIME_PATH="$(command -v "${TENV_RUNTIME_CMD}")"
JQ_PATH="$(command -v jq)"
ln -s "${RUNTIME_PATH}" "${SAFE_BIN_DIR}/$(basename -- "${TENV_RUNTIME_CMD}")"
ln -s "${JQ_PATH}" "${SAFE_BIN_DIR}/jq"
DVCODE_PATH="${REPO_DIR}/code.sh"
out="$(HOME="${TENV_FAKE_HOME}" PATH="${SAFE_BIN_DIR}:/usr/bin:/bin" "${DVCODE_PATH}" -v tplancode 2>&1)" \
  && dv::fail "expected failure when 'code' is not in PATH" || true
[[ "${out}" == *"VS Code CLI 'code' not found in PATH"* ]] \
  || dv::fail "expected \"code\" not-found message, got: ${out}"

# Step 3: pre-seed devbox_config with unrelated blocks that must survive
# untouched (proves no cross-match, no collateral damage to other profiles)
mkdir -p "${TENV_FAKE_HOME}/.ssh"
cat > "${TENV_FAKE_HOME}/.ssh/devbox_config" <<'EOF'
Host devbox-other
  HostName localhost
  Port 12345
  User bob
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host devbox-tplancode2
  HostName localhost
  Port 22222
  User bob
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF

# Step 4: fake 'code' shim to capture invocation arguments
FAKE_BIN_DIR="$(mktemp -d)"
CODE_SHIM_LOG="$(mktemp)"
cat > "${FAKE_BIN_DIR}/code" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${CODE_SHIM_LOG:?}"
SHIM
chmod +x "${FAKE_BIN_DIR}/code"

dv::run_code() {
  PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" CODE_SHIM_LOG="${CODE_SHIM_LOG}" \
    bash "${REPO_DIR}/code.sh" -v tplancode
}

out="$(dv::run_code 2>&1)" || dv::fail "code.sh failed: ${out}"

# Step 5: assert code was invoked with exactly the right arguments
LOGGED_LINE_COUNT="$(wc -l < "${CODE_SHIM_LOG}" | tr -d ' ')"
LOGGED_CONTENT="$(cat "${CODE_SHIM_LOG}")"
ARG0="$(sed -n '1p' "${CODE_SHIM_LOG}")"
ARG1="$(sed -n '2p' "${CODE_SHIM_LOG}")"
[[ "${LOGGED_LINE_COUNT}" -eq 2 ]] \
  || dv::fail "expected 2 args logged to code, got ${LOGGED_LINE_COUNT}: ${LOGGED_CONTENT}"
[[ "${ARG0}" == '--folder-uri' ]] || dv::fail "arg0 mismatch: ${ARG0}"
[[ "${ARG1}" == 'vscode-remote://ssh-remote+devbox-tplancode/workspace' ]] \
  || dv::fail "arg1 mismatch: ${ARG1}"

# Step 6: assert permissions and block content
SSH_DIR_MATCH="$(find "${TENV_FAKE_HOME}/.ssh" -maxdepth 0 -perm 700 2>/dev/null)"
[[ -n "${SSH_DIR_MATCH}" ]] || dv::fail "expected ~/.ssh to be exactly 700"
CONFIG_FILE_MATCH="$(find "${TENV_FAKE_HOME}/.ssh/devbox_config" -maxdepth 0 -perm 600 2>/dev/null)"
[[ -n "${CONFIG_FILE_MATCH}" ]] || dv::fail "expected devbox_config to be exactly 600"
grep -qx "Host devbox-tplancode" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected 'Host devbox-tplancode' block in devbox_config"
grep -q "Port ${port}" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected 'Port ${port}' in devbox_config"

# Step 7: assert the unrelated pre-seeded blocks are untouched
grep -qx "Host devbox-other" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected pre-existing 'Host devbox-other' block to survive"
grep -qx "Host devbox-tplancode2" "${TENV_FAKE_HOME}/.ssh/devbox_config" \
  || dv::fail "expected pre-existing 'Host devbox-tplancode2' block to survive"

FIRST_RUN_HASH="$(sha256sum "${TENV_FAKE_HOME}/.ssh/devbox_config" | awk '{print $1}')"

# Step 8: re-run twice more; content must be byte-identical each time
# (regression test for a blank-line-accumulation bug caught during design
# review, before it ever shipped)
for _ in 1 2; do
  out="$(dv::run_code 2>&1)" || dv::fail "re-run of code.sh failed: ${out}"
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
