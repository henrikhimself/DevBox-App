#!/usr/bin/env bash
# Docker frontend loader: sourced by the lifecycle wrappers. Loads the Docker
# runtime adapter (which runs the host/engine preflight first), then the
# runtime-neutral libraries.

_HJ_DOCKER_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HJ_COMMON_HOST="$(cd -P "${_HJ_DOCKER_DIR}/../Common/host" && pwd)"

# shellcheck source=runtime/adapter.sh
source "${_HJ_DOCKER_DIR}/runtime/adapter.sh"
# shellcheck source=../Common/host/lib/common.sh
source "${_HJ_COMMON_HOST}/lib/common.sh"
# shellcheck source=../Common/host/lib/container.sh
source "${_HJ_COMMON_HOST}/lib/container.sh"
# shellcheck source=../Common/host/lib/forwards.sh
source "${_HJ_COMMON_HOST}/lib/forwards.sh"
# shellcheck source=../Common/host/lib/profiles.sh
source "${_HJ_COMMON_HOST}/lib/profiles.sh"
# shellcheck source=../Common/host/lib/ssh.sh
source "${_HJ_COMMON_HOST}/lib/ssh.sh"
