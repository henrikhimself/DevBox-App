#!/usr/bin/env bash
set -uo pipefail

# F59 - discard removes the ssh config block for the discarded profile

# shellcheck source=testenv.sh
source "$(dirname "${BASH_SOURCE[0]}")/testenv.sh"

dv::fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

dv::cleanup() {
  dv::volume_rm devbox-tplandscfg devbox-tplandscfg-docker
  dv::cleanup_fake_home
}
trap dv::cleanup EXIT

# The repository scripts live one level up from this tests/ directory; tests
# invoke them directly by path.
REPO_DIR="${TENV_FRONTEND_DIR}"

# Preflight
[[ -f "${REPO_DIR}/init.sh" ]] || dv::fail "./init.sh not found at ${REPO_DIR}"
[[ -f "${REPO_DIR}/discard.sh" ]] || dv::fail "./discard.sh not found at ${REPO_DIR}"

# Safety: confirm the real ~/.ssh/devbox_config (this test process's own
# actual HOME, never overridden below) is untouched by this test.
REAL_DEVBOX_CONFIG="${HOME}/.ssh/devbox_config"
BEFORE_HASH=''
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  BEFORE_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
fi

dv::make_fake_home

# Step 1: seed the fake devbox_config with the target profile's block (the
# shape dv::prepare_ssh_alias writes) plus an unrelated block that must
# survive untouched (proves no cross-match, no collateral damage).
CONFIG_FILE="${TENV_FAKE_HOME}/.ssh/devbox_config"
mkdir -p "${TENV_FAKE_HOME}/.ssh"
cat > "${CONFIG_FILE}" <<'EOF'
Host devbox-other
  HostName localhost
  Port 2200
  User bob
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host devbox-tplandscfg
  HostName localhost
  Port 2201
  User bob
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
chmod 600 "${CONFIG_FILE}"

# Step 2: initialize the profile (volumes only, no container)
bash "${REPO_DIR}/init.sh" tplandscfg >/dev/null 2>&1 || dv::fail "init.sh tplandscfg failed"
dv::volume_exists devbox-tplandscfg \
  || dv::fail "setup: volume devbox-tplandscfg missing"

# Step 3: discard under the fake HOME (only the fake config is writable)
HOME="${TENV_FAKE_HOME}" bash "${REPO_DIR}/discard.sh" -y tplandscfg >/dev/null 2>&1 \
  || dv::fail "discard.sh -y tplandscfg failed"

# Step 4: the target block is gone, the unrelated block survives
config_content="$(cat "${CONFIG_FILE}")"
if grep -qx 'Host devbox-tplandscfg' "${CONFIG_FILE}"; then
  dv::fail "expected the 'Host devbox-tplandscfg' block to be removed, got: ${config_content}"
fi
if grep -qx '  Port 2201' "${CONFIG_FILE}"; then
  dv::fail "expected the target block's body to be removed, got: ${config_content}"
fi
grep -qx 'Host devbox-other' "${CONFIG_FILE}" \
  || dv::fail "expected the unrelated 'Host devbox-other' block to survive, got: ${config_content}"
grep -qx '  Port 2200' "${CONFIG_FILE}" \
  || dv::fail "expected the unrelated block's body to survive, got: ${config_content}"

# Step 5: config file permissions are preserved
PERM_MATCH="$(find "${CONFIG_FILE}" -maxdepth 0 -perm 600 2>/dev/null)"
[[ -n "${PERM_MATCH}" ]] || dv::fail "expected devbox_config to be exactly 600 after discard"

# Step 6: the volumes are still removed (no regression in core behavior)
dv::volume_exists devbox-tplandscfg \
  && dv::fail "volume devbox-tplandscfg still exists after discard" || true
dv::volume_exists devbox-tplandscfg-docker \
  && dv::fail "volume devbox-tplandscfg-docker still exists after discard" || true

# Step 7: re-discard on the now-empty profile still hits the unchanged gate
out="$(HOME="${TENV_FAKE_HOME}" bash "${REPO_DIR}/discard.sh" -y tplandscfg 2>&1)" \
  && dv::fail "expected re-discard to dv::fail with no volumes" || true
[[ "${out}" == *"no volumes to discard"* ]] \
  || dv::fail "expected the 'no volumes to discard' error, got: ${out}"

# Verify the real ~/.ssh/devbox_config was never touched by any of the above
if [[ -f "${REAL_DEVBOX_CONFIG}" ]]; then
  AFTER_HASH="$(sha256sum "${REAL_DEVBOX_CONFIG}" | awk '{print $1}')"
  [[ "${BEFORE_HASH}" == "${AFTER_HASH}" ]] || dv::fail "real ~/.ssh/devbox_config was modified!"
elif [[ -n "${BEFORE_HASH}" ]]; then
  dv::fail "real ~/.ssh/devbox_config existed before but is now missing!"
fi

printf 'PASS\n'
