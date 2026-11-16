# Agent instructions (Docker specialization)

## Project Overview

This directory builds and manages the DevBox image (`localhost:5000/hj/devbox-docker`, tag centralized in `Common/image/tag.txt`), the
Docker Engine variant of the DevBox image (SSH on port 2222, Visual Studio Code
Remote-SSH supported).

- Supported host: **native Linux amd64** with a **local, rootful** Docker Engine
  reached over a **Unix socket**, **no `userns-remap`**. Nothing else is
  supported: no arm64, no emulation, no macOS/Windows, no remote/`ssh://`/`tcp://`
  endpoints, no rootless outer Engine, no automatic fallback to another runtime.
  Never infer outer-rootless support from the in-guest rootless daemon.
- The image targets `linux/amd64` from the pinned `debian:trixie-<date>` base (`FROM` in `Common/image/Containerfile`). It has no swap
  service and no Apple-specific options (`--no-dns`, tmpfs).
- User guide:
  [`README.md`](README.md).
- Runtime status: **not verified on a real host**. Say so when describing it;
  static/stub results are not runtime evidence.

## Layout

- `init.sh run.sh stop.sh show.sh discard.sh backup.sh restore.sh ssh.sh code.sh
  forward.sh`: thin wrappers. Each sources `shared.sh` and then
  `../Common/host/commands/<name>.sh`. Policy lives in `Common/host`, not here.
- `shared.sh`: loads `runtime/adapter.sh`, then `../Common/host/lib/*.sh`.
- `runtime/adapter.sh`: **every** `docker` CLI/JSON call (type-specific
  `docker container|image|volume`), metadata normalization, launch flags and
  helper containers. Sourcing it runs the host/engine preflight first.
- `runtime/preflight.sh`: the single implementation of the host/engine checks
  (also used by `make`). Read-only.
- `runtime/throwaway.sh`: `make run` launcher (same flag source as profiles).
- `runtime/image/s6-x/`: Docker-only s6 hook scripts overlaid onto the shared
  `Common/image/s6-x` (no swap; devices come from the passthrough).
- `Makefile`, `arch.mk`: Docker platform names and targets; shared rules in
  `../Common/build/common.mk`.
- `tests/run-tests.sh`: leaf runner for the shared feature suite.

## Rules

- Approved launch flags only: `--privileged --cap-add ALL` (decision).
  No host Docker socket, no extra
  devices/mounts/namespaces/sysctls, no explicit `--device`/`--security-opt`.
  If the guest daemon cannot start, report the blocker; do not add privileges.
- Archive helpers (`--entrypoint /bin/bash`) get only their mounts: never the
  launch privileges.
- Do not duplicate shared policy here; change `Common/host` and both variants
  follow. Do not add Docker JSON handling outside `runtime/adapter.sh`.
- `DOCKER_CMD` must name `docker`. Never switch contexts or start a daemon.
- Absent objects are not errors; daemon/permission/parse failures are (rc 2 with
  a message). Image or volume with a container's name must never satisfy a
  container lookup.

## Building

```sh
make -C Docker preflight && make -C Docker build
```

Downloads go to `Docker/tmp/` (git-ignored) and are SHA-256 verified; the
context is `Docker/tmp/build-context` (assembled from an allowlist; do not edit
it by hand).

## Testing

- Feature suite: `Docker/tests/run-tests.sh` (`DEVBOX_TEST_ONLY="F48 F51"`;
  `DEVBOX_TEST_FAKE_HOST=1` only for development self-checks). Real tests require
  the supported host and no `devbox-*` containers; never remove containers you did
  not create.

## Secrets and required modes

Same as the shared rules: never print `authorized_keys`, private keys or the
root CA; inspect them by checksum and mode only. The protected inputs and modes
are enforced by `prepare-context.sh` (checksum + mode, on disk `0400`/`0600`;
in the image `0400`/`0600`/`0444`).
