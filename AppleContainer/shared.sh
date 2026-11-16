#!/usr/bin/env bash
# Apple Container frontend loader: sourced by the lifecycle wrappers.
# Loads the Apple runtime adapter, then the runtime-neutral libraries.

_HJ_APPLE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HJ_COMMON_HOST="$(cd -P "${_HJ_APPLE_DIR}/../Common/host" && pwd)"

# shellcheck source=runtime/adapter.sh
source "${_HJ_APPLE_DIR}/runtime/adapter.sh"
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
