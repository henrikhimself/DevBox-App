#!/usr/bin/env bash
set -euo pipefail

# Shared command body: sourced by the runtime frontend (AppleContainer/code.sh,
# Docker/code.sh), which has already sourced its shared.sh (adapter + libraries).

dv::require_jq

dv::usage() {
  cat <<'EOF'
Usage: [options]

Options:
  -v profile-name  Optional profile name selecting which devbox profile to connect to; auto-detected if omitted and exactly one is running

Opens VS Code (Remote-SSH) against the running devbox container for the
given profile. The profile must already be running (via run.sh, with or
without -k).
EOF
}

while getopts ':v:' opt; do
  case "${opt}" in
    v)
      PROFILE_NAME="${OPTARG}"
      ;;
    :)
      dv::opt_error ':' "${OPTARG}" dv::usage
      ;;
    \?)
      dv::opt_error '?' "${OPTARG}" dv::usage
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ $# -ne 0 ]]; then
  dv::usage
  exit 1
fi

dv::ensure_container_backend_running

dv::resolve_running_devbox "${PROFILE_NAME:-}"
dv::prepare_ssh_alias

if ! command -v code >/dev/null 2>&1; then
  printf '%s\n' "❌ VS Code CLI 'code' not found in PATH." >&2
  printf '%s\n' "Install it from VS Code: Cmd+Shift+P → 'Shell Command: Install code command in PATH'." >&2
  exit 1
fi

printf '%s\n' "🚀 Opening VS Code for profile '${PROFILE_NAME}' (${CONTAINER_NAME}, port ${PORT})..."
code --folder-uri "vscode-remote://ssh-remote+${ALIAS}${TARGET_PATH}"
