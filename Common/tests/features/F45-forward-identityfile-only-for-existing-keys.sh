#!/usr/bin/env bash
set -uo pipefail

# F45 - forward passes IdentityFile only for existing readable keys

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::container_rm devbox-tplanfwdid
  dv::cleanup_fake_home
  dv::cleanup_tmpdir
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/forward.sh" ]] || dv::fail "./forward.sh not found at ${REPO_DIR}"

dv::ensure_image busybox:latest
dv::make_tmpdir
dv::make_fake_home

# Step 1: running fixture container for the target profile.
dv::container_rm devbox-tplanfwdid
ssh_port="$(dv::free_port)"
dv::container_run_detached \
  --name devbox-tplanfwdid \
  -p "${ssh_port}:2222" \
  busybox:latest sh -c 'sleep 600'

# Step 2: fake ssh shim logs full argument vectors and exits success.
FAKE_BIN="${TENV_TMPDIR}/bin"
SSH_LOG="${TENV_TMPDIR}/ssh.log"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SSH_LOG_FILE:?}"
EOF
chmod 755 "${FAKE_BIN}/ssh"

mkdir -p "${TENV_FAKE_HOME}/.ssh"

# Step 3: with no readable key files, forward.sh must not pass IdentityFile.
port_a="$(dv::free_port)"
: > "${SSH_LOG}"
out="$(SSH_LOG_FILE="${SSH_LOG}" HOME="${TENV_FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" \
  bash "${REPO_DIR}/forward.sh" -v tplanfwdid -p "${port_a}:443" 2>&1)" || dv::fail "forward.sh case A failed: ${out}"
if grep -q 'IdentityFile=' "${SSH_LOG}"; then
  ssh_log_content="$(cat "${SSH_LOG}")"
  dv::fail "did not expect IdentityFile args when no keys exist, got: ${ssh_log_content}"
fi

# Step 4: with one readable key file, forward.sh must pass exactly that IdentityFile.
key_path="${TENV_FAKE_HOME}/.ssh/id_ed25519"
printf '%s\n' 'dummy-key' > "${key_path}"
chmod 600 "${key_path}"

port_b="$(dv::free_port)"
: > "${SSH_LOG}"
out="$(SSH_LOG_FILE="${SSH_LOG}" HOME="${TENV_FAKE_HOME}" PATH="${FAKE_BIN}:${PATH}" \
  bash "${REPO_DIR}/forward.sh" -v tplanfwdid -p "${port_b}:443" 2>&1)" || dv::fail "forward.sh case B failed: ${out}"

identity_matches="$(grep -o 'IdentityFile=[^ ]*' "${SSH_LOG}" || true)"
match_count="$(printf '%s\n' "${identity_matches}" | grep -c . || true)"
[[ "${match_count}" -eq 1 ]] \
  || {
    ssh_log_content="$(cat "${SSH_LOG}")"
    dv::fail "expected exactly one IdentityFile arg, got ${match_count}: ${ssh_log_content}"
  }
[[ "${identity_matches}" == "IdentityFile=${key_path}" ]] \
  || dv::fail "unexpected IdentityFile arg: ${identity_matches}"

printf 'PASS\n'
