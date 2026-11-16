#!/usr/bin/env bash
# run-suite.sh — runs the DevBox first-run installer tests.
#
# These are stub-backed, host-independent unit tests: no TTY, no network, no
# real runtime. The two modules cover:
#   * test_install_devbox.py          — the orchestrator (menu, dependency
#                                       ordering, transitive-closure selection).
#   * test_firstrun_installers.py     — the eight installer payloads and the
#                                       thin login-guard shim contract.
#
# Usage:
#   bash run-suite.sh
#   # or, equivalently, from the repository root:
#   python3 -m unittest Common.tests.firstrun.test_install_devbox \
#                       Common.tests.firstrun.test_firstrun_installers
#
# The script cd's to the repository root first so the dotted-namespace module
# path resolves regardless of where it is invoked from, and exits non-zero if
# any test fails.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# firstrun/ <─ tests/ <─ Common/ <─ workspace root
repo_root="$(cd "${script_dir}/../../../" && pwd)"

if [[ ! -f "${script_dir}/test_install_devbox.py" \
   || ! -f "${script_dir}/test_firstrun_installers.py" ]]; then
  printf '%s\n' \
    '❌ test files missing: expected test_install_devbox.py and test_firstrun_installers.py beside this script.' >&2
  exit 1
fi

cd "${repo_root}" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' '❌ python3 not found on PATH; the first-run tests require python3 (3.9+).' >&2
  exit 127
fi

python3 -m unittest \
  Common.tests.firstrun.test_install_devbox \
  Common.tests.firstrun.test_firstrun_installers
exit $?
