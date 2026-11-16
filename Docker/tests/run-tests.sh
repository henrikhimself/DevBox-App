#!/usr/bin/env bash
# Docker leaf runner for the shared feature suite (../../Common/tests/features).
# Real-runtime tests need native Linux amd64 with a rootful local Docker Engine
# and no devbox-* containers (the frontends enforce the platform preflight).
# `DEVBOX_TEST_ONLY` can restrict to stub tests.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVBOX_TEST_RUNTIME=docker
DEVBOX_FRONTEND_DIR="$(cd "${HERE}/.." && pwd)"
export DEVBOX_FRONTEND_DIR
exec bash "${HERE}/../../Common/tests/features/run-suite.sh" "$@"
