#!/usr/bin/env bash
# Host SSH alias policy shared by all frontends: the script-owned
# ~/.ssh/devbox_config (never the user's ~/.ssh/config). Runtime facts come from
# the adapter (dv::container_ssh_host_port, dv::workspace_target_path).
# Sourced, never executed. Bash 3.2 compatible.

# Removes the given profile's Host block from the script-owned
# ~/.ssh/devbox_config (inverse of the block write in
# dv::prepare_ssh_alias). No-op when the config file or the block does not
# exist. Writes the file back atomically (mktemp + mv) and keeps it at 600,
# with no leading/trailing blank lines. Used by discard.sh so discarding a
# profile also removes its ssh alias.
dv::remove_ssh_host_block() {
  local profile_name="${1}"
  local config_file="${HOME}/.ssh/devbox_config"

  [[ -f "${config_file}" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp "${config_file}.XXXXXX")"

  # Remove this alias's block (exact "Host <alias>" match), stopping at the
  # next "Host " line.
  awk -v host_line="Host devbox-${profile_name}" '
    $0 == host_line { skip = 1; next }
    skip && /^Host / { skip = 0 }
    skip { next }
    { print }
  ' "${config_file}" > "${tmp_file}"

  # Strip leading blank lines (awk) and trailing blank lines (command
  # substitution) so the file never starts or ends with blanks even when the
  # removed block sat at the top or bottom of the file.
  local remaining
  remaining="$(awk 'NF { started = 1 } started { print }' "${tmp_file}")"
  if [[ -n "${remaining}" ]]; then
    printf '%s\n' "${remaining}" > "${tmp_file}"
  else
    : > "${tmp_file}"
  fi

  mv "${tmp_file}" "${config_file}"
  chmod 600 "${config_file}"
}

# For the already-resolved PROFILE_NAME/CONTAINER_NAME, rewrites this profile's
# block in the script-owned ~/.ssh/devbox_config (never the user's ~/.ssh/config)
# so code.sh/ssh.sh resolve the devbox-<profile> alias with the current port.
# Sets globals PORT, TARGET_PATH, ALIAS. Exits 1 if the port can't be found.
# Warns (non-blocking) if ~/.ssh/config lacks the Include line.
dv::prepare_ssh_alias() {
  # shellcheck disable=SC2034 # used by callers after this function returns
  PORT="$(dv::container_ssh_host_port "${CONTAINER_NAME}")"
  if [[ -z "${PORT}" ]]; then
    # shellcheck disable=SC2153 # PROFILE_NAME is a caller-set global
    printf '%s\n' "❌ Could not determine the SSH port for profile '${PROFILE_NAME}'." >&2
    exit 1
  fi

  # shellcheck disable=SC2034 # used by callers after this function returns
  TARGET_PATH="$(dv::workspace_target_path "${CONTAINER_NAME}")"
  if [[ -z "${TARGET_PATH}" ]]; then
    TARGET_PATH='/workspace'
  fi

  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  local config_file="${HOME}/.ssh/devbox_config"
  touch "${config_file}"
  chmod 600 "${config_file}"

  # shellcheck disable=SC2034 # used by callers after this function returns
  ALIAS="devbox-${PROFILE_NAME}"

  # Remove this alias's existing block, then append a fresh one below. The
  # file is left without leading/trailing blank lines, so exactly one blank
  # line always separates blocks however many times this one was replaced.
  dv::remove_ssh_host_block "${PROFILE_NAME}"
  local tmp_file
  tmp_file="$(mktemp "${config_file}.XXXXXX")"

  local remaining
  remaining="$(cat "${config_file}")"
  {
    if [[ -n "${remaining}" ]]; then
      printf '%s\n\n' "${remaining}"
    fi
    cat <<EOF
Host ${ALIAS}
  HostName localhost
  Port ${PORT}
  User bob
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
  } > "${tmp_file}"

  mv "${tmp_file}" "${config_file}"
  chmod 600 "${config_file}"

  local ssh_config="${HOME}/.ssh/config"
  if [[ ! -f "${ssh_config}" ]] || ! grep -qE '^[[:space:]]*Include[[:space:]]+.*devbox_config' "${ssh_config}"; then
    printf '%s\n' "⚠️  ~/.ssh/config doesn't appear to Include ~/.ssh/devbox_config yet." >&2
    printf '%s\n' "Add this line near the top of ~/.ssh/config, then retry:" >&2
    printf '%s\n' "  Include ~/.ssh/devbox_config" >&2
  fi
}
