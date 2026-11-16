#!/usr/bin/env bash
set -uo pipefail

# F24 - code auto-detect and multi-running error
#
# Precondition: no devbox-* containers may be running when this test starts.

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplancodeauto devbox-tplancodeauto2
  dv::cleanup_fake_home
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/code.sh" ]] || dv::fail "./code.sh not found at ${REPO_DIR}"
if dv::running_devbox_names | grep -q .; then
  printf '%s\n' '❌ Other devbox containers are already running on this host.'
  printf '%s\n' 'F24 tests host-wide auto-detect/multi-running behavior and requires a clean state.'
  printf '%s\n' 'Stop each running devbox first (./stop.sh -v <profile-name> for each one shown below), then retry.'
  dv::running_devbox_names >&2
  exit 1
fi

# Safety: confirm the real ~/.ssh/devbox_config (this test process's own
# actual HOME, never overridden below) is untouched by this test.
REAL_DEVBOX_CONFIG="${HOME}/.ssh/devbox_config"
BEFORE_HASH=''
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  BEFORE_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
fi

dv::ensure_image busybox:latest
dv::make_fake_home

# Fake 'code' shim so a successful run doesn't require real VS Code
FAKE_BIN_DIR="$(mktemp -d)"
CODE_SHIM_LOG="$(mktemp)"
cat > "${FAKE_BIN_DIR}/code" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${CODE_SHIM_LOG:?}"
SHIM
chmod +x "${FAKE_BIN_DIR}/code"

# Step 1: start exactly one devbox container, with a published port since
# code.sh (unlike stop.sh) needs one to resolve the SSH port
dv::container_rm devbox-tplancodeauto devbox-tplancodeauto2
port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplancodeauto \
  -p "${port}:2222" \
  busybox:latest sh -c 'sleep 600'

# Step 2: code.sh with no -v must auto-detect and connect to it
out="$(PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" CODE_SHIM_LOG="${CODE_SHIM_LOG}" \
  bash "${REPO_DIR}/code.sh" 2>&1)" || dv::fail "code.sh failed to auto-detect single running devbox: ${out}"
[[ "${out}" == *"devbox-tplancodeauto"* ]] \
  || dv::fail "expected auto-detected container 'devbox-tplancodeauto' in output, got: ${out}"
ARG1="$(sed -n '2p' "${CODE_SHIM_LOG}")"
[[ "${ARG1}" == 'vscode-remote://ssh-remote+devbox-tplancodeauto/workspace' ]] \
  || dv::fail "expected code to be invoked for devbox-tplancodeauto, got: ${ARG1}"

# Step 3: start a second devbox container
dv::container_run_detached --name devbox-tplancodeauto2 busybox:latest sh -c 'sleep 600'

# Step 4: code.sh must error when multiple are running
out="$(PATH="${FAKE_BIN_DIR}:${PATH}" HOME="${TENV_FAKE_HOME}" CODE_SHIM_LOG="${CODE_SHIM_LOG}" \
  bash "${REPO_DIR}/code.sh" 2>&1)" && dv::fail "expected failure for multiple running devboxes" || true
[[ "${out}" == *"Multiple devbox containers found"* ]] \
  || dv::fail "expected 'Multiple devbox containers found' in output, got: ${out}"
[[ "${out}" == *"tplancodeauto"* && "${out}" == *"tplancodeauto2"* ]] \
  || dv::fail "expected both profile names in the multi-running message, got: ${out}"

# Verify the real ~/.ssh/devbox_config was never touched
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  AFTER_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
  [[ "${BEFORE_HASH}" == "${AFTER_HASH}" ]] || dv::fail "real ~/.ssh/devbox_config was modified!"
elif [[ -n "${BEFORE_HASH}" ]]; then
  dv::fail "real ~/.ssh/devbox_config existed before but is now missing!"
fi

printf 'PASS\n'
