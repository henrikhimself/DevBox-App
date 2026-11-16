#!/usr/bin/env bash
set -euo pipefail

GH_PASS_ENTRY="gh/github.com"
GH_HOSTS_FILE="${HOME}/.config/gh/hosts.yml"

if ! command -v gh >/dev/null 2>&1; then
  printf '%s\n' 'Error: gh is not installed.' >&2
  exit 1
fi

if ! command -v pass >/dev/null 2>&1; then
  printf '%s\n' 'Error: pass is not installed.' >&2
  exit 1
fi

TOKEN="$(gh auth token 2>/dev/null)"
if [[ -z "${TOKEN}" ]]; then
  printf '%s\n' 'Error: no gh auth token found. Run "gh auth login" first.' >&2
  exit 1
fi

printf '%s\n' "${TOKEN}" | pass insert -m -f "${GH_PASS_ENTRY}"

# Remove plaintext credential file so gh relies on GH_TOKEN going forward.
if [[ -f "${GH_HOSTS_FILE}" ]]; then
  rm -f "${GH_HOSTS_FILE}"
  printf '%s\n' "Removed plaintext credential file: ${GH_HOSTS_FILE}"
fi

printf '%s\n' ""
printf '%s\n' "Token stored in pass at '${GH_PASS_ENTRY}'."
printf '%s\n' 'GH_TOKEN will be exported automatically on future logins via 99-gh-credential.sh.'
printf '%s\n' "To take effect in the current session, run: export GH_TOKEN=\"\$(pass show ${GH_PASS_ENTRY})\""
