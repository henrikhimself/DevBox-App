#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -h "${SCRIPT_SOURCE}" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
  SCRIPT_SOURCE="$(readlink "${SCRIPT_SOURCE}")"
  [[ "${SCRIPT_SOURCE}" != /* ]] && SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
# shellcheck source=shared.sh
source "${SCRIPT_DIR}/shared.sh"
# shellcheck source=../Common/host/commands/restore.sh
source "${SCRIPT_DIR}/../Common/host/commands/restore.sh"
