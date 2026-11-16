#!/usr/bin/env bash
# `make run` launcher: an interactive, throwaway devbox container with the
# common SSH publication and the approved Docker flag set. The flags come from
# the same adapter function the profile lifecycle uses (single source).
#
#   throwaway.sh <image>
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:?usage: throwaway.sh <image>}"

# Sourcing the adapter runs the build-mode host/engine preflight first.
# shellcheck source=adapter.sh
source "${HERE}/adapter.sh"
dv::docker_require_launch

if ! dv::image_exists "${IMAGE}"; then
  printf '%s\n' "❌ Image ${IMAGE} not found. Build it first: make build" >&2
  exit 1
fi

dv::docker_launch_flags
exec "${DOCKERPF_CMD}" container run -it --rm --name devbox \
  -p 2222:2222/tcp \
  "${HJ_DOCKER_LAUNCH_FLAGS[@]}" \
  "${IMAGE}"
