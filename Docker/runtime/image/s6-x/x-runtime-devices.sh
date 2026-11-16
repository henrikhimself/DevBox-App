#!/usr/bin/env bash
# Docker guest: /dev/fuse and /dev/net/tun are passed through by
# `docker run --device`. Validate them; never create device nodes. A missing
# or inaccessible device is a launch error and fails the dockerd service.
for dev in /dev/fuse /dev/net/tun; do
  if [ ! -c "${dev}" ]; then
    printf '%s\n' "dockerd: ${dev} is missing; launch with --device ${dev}" >&2
    exit 1
  fi
  # shellcheck disable=SC2016 # $1 is expanded by the inner sh, not here
  if ! s6-setuidgid bob sh -c 'test -r "$1" && test -w "$1"' _ "${dev}"; then
    printf '%s\n' "dockerd: ${dev} is not readable/writable by bob" >&2
    exit 1
  fi
done
exit 0
