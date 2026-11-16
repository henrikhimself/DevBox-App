#!/usr/bin/env bash
# `make run` launcher: an interactive, throwaway devbox container with the
# common SSH publication and the approved Apple flag set. The flags come from
# the same adapter the profile lifecycle uses (single source), so the Makefile
# never duplicates a flag.
#
#   throwaway.sh <image>
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:?usage: throwaway.sh <image>}"

# Sourcing the adapter resolves and pins the `container` CLI and provides the
# flag source; the launch preflight validates the host and backend. It never
# starts, reconfigures or switches the backend (that is the CLI's job, never
# this script's).
# shellcheck source=adapter.sh
source "${HERE}/adapter.sh"
# shellcheck source=preflight.sh
source "${HERE}/preflight.sh"
dv::check launch || exit 1

if ! dv::image_exists "${IMAGE}"; then
  printf '%s\n' "❌ Image ${IMAGE} not found. Build it first: make build" >&2
  exit 1
fi

dv::run_flags
exec "${CONTAINER_CMD}" run -it --rm --name devbox \
  -p 2222:2222/tcp \
  "${HJ_RUN_FLAGS[@]}" \
  "${IMAGE}"
