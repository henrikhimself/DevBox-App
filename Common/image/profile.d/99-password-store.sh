#!/usr/bin/env sh
# shellcheck disable=SC2317 # This profile is sourced indirectly by interactive shell startup.
GPG_ID="user@localhost"
PASSWORD_STORE_DIR="${HOME}/.password-store"

# Run only for interactive logins
case "$-" in
  *i*) ;;
  *) return 2>/dev/null; exit 0 ;;
esac

# Set GPG_TTY for SSH sessions
if [ -t 0 ]; then
  GPG_TTY="$(tty)"
  export GPG_TTY
fi

# Ensure ~/.gnupg exists
GNUPG_DIR="${HOME}/.gnupg"
mkdir -p "${GNUPG_DIR}"
chmod 700 "${GNUPG_DIR}"

# 3. Configure pinentry to use terminal pinentry
printf 'pinentry-program %s\n' '/usr/bin/pinentry-tty' > "${GNUPG_DIR}/gpg-agent.conf"
printf 'default-cache-ttl %s\n' '31536000' >> "${GNUPG_DIR}/gpg-agent.conf"
printf 'max-cache-ttl %s\n' '31536000' >> "${GNUPG_DIR}/gpg-agent.conf"
chmod 600 "${GNUPG_DIR}/gpg-agent.conf"

# Restart gpg-agent so new config takes effect
if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --kill gpg-agent 2>/dev/null
fi

# Check once whether the configured key already exists.
HAS_SECRET_KEY=0
if gpg --list-secret-keys --with-colons "${GPG_ID}" >/dev/null 2>&1; then
  HAS_SECRET_KEY=1
fi

# Generate a noninteractive GPG key with NO passphrase if none exists
if [ "${HAS_SECRET_KEY}" -eq 0 ]; then
  TMP_BATCH="$(mktemp)"
  cat > "${TMP_BATCH}" <<EOF
%no-protection
Key-Type: RSA
Key-Length: 2048
Name-Real: ${GPG_ID}
Name-Comment: ephemeral-container-key
Name-Email: ${GPG_ID}
Expire-Date: 0
EOF
  # Generate key noninteractively without passphrase
  gpg --batch --generate-key "${TMP_BATCH}" >/dev/null 2>&1 || {
    rm -f "${TMP_BATCH}"
    printf '%s\n' 'Warning: gpg key generation failed' >&2
  }
  rm -f "${TMP_BATCH}"
fi

# Ensure password store directory exists and is writable
mkdir -p "${PASSWORD_STORE_DIR}"
chmod 700 "${PASSWORD_STORE_DIR}"

# pass requires .gpg-id; initialize the store if missing.
if [ ! -f "${PASSWORD_STORE_DIR}/.gpg-id" ]; then
  pass init "${GPG_ID}" >/dev/null 2>&1 || {
    printf '%s\n' "Warning: pass init failed for ${GPG_ID}" >&2
  }
fi

# pass-git-helper is the git credential helper that reads secrets from pass.
git config --global credential.helper '!pass-git-helper $@'

# Provide a default host-to-entry mapping if none exists yet.
PASS_GIT_HELPER_DIR="${HOME}/.config/pass-git-helper"
PASS_GIT_MAPPING_FILE="${PASS_GIT_HELPER_DIR}/git-pass-mapping.ini"
mkdir -p "${PASS_GIT_HELPER_DIR}"
chmod 700 "${PASS_GIT_HELPER_DIR}"

if [ ! -f "${PASS_GIT_MAPPING_FILE}" ]; then
  cat > "${PASS_GIT_MAPPING_FILE}" << 'EOF'
[DEFAULT]
target=git/${host}
EOF
  chmod 600 "${PASS_GIT_MAPPING_FILE}"
fi

