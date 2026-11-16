#!/usr/bin/env bash
# Apple Container leaf runner for the shared feature suite
# (../../Common/tests/features). Needs Apple Container on macOS arm64 for the
# real-runtime tests; `DEVBOX_TEST_ONLY` can restrict to stub tests.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVBOX_TEST_RUNTIME=apple
DEVBOX_FRONTEND_DIR="$(cd "${HERE}/.." && pwd)"
export DEVBOX_FRONTEND_DIR
exec bash "${HERE}/../../Common/tests/features/run-suite.sh" "$@"
