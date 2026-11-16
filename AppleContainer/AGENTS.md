# Agent instructions

## Project Overview

This repository builds the DevBox image (`localhost:5000/hj/devbox-apple`, tag centralized in `Common/image/tag.txt`), a self-contained
development environment image used via SSH on port 2222. Both the `ssh`
client and the Visual Studio Code `Remote SSH` extension are supported
access methods.

- Apple Container is the only supported container runtime.
- The host baseline is Darwin arm64 (Apple-silicon macOS).
- The image tag is centralized in `Common/image/tag.txt`.
- The build targets `linux/arm64` from the pinned `debian:trixie-<date>` base (`FROM` in `Common/image/Containerfile`).
- The in-guest rootless Docker daemon with the persistent `/data/docker`
  volume is fully supported functionality.
- This repository is the only Git repository for this project. Never copy
  nested or foreign `.git` directories into this tree.

## Layout

- This directory: thin lifecycle wrappers (`init.sh`, `backup.sh`, `restore.sh`,
  `run.sh`, `stop.sh`, `show.sh`, `discard.sh`, `code.sh`, `ssh.sh`, `forward.sh`;
  each sources `shared.sh`, then `../Common/host/commands/<name>.sh`), `shared.sh`,
  `runtime/adapter.sh` (all `container` CLI/JSON calls and the `make run` flag source), `runtime/preflight.sh` (read-only host/backend check, also used by make), `runtime/throwaway.sh` (`make run` launcher, same flag source as profiles), `runtime/image/s6-x/`
  (Apple-only guest hooks: swap, device creation), `Makefile`, `arch.mk`
- `../Common/image/`: shared image definition (`Containerfile`, `s6-x/`,
  `profile.d/`, `firstrun.d/`, `script/`); `../Common/build/`: shared build rules and
  context preparation; `../Common/host/`: shared lifecycle policy
- `tests/run-tests.sh`: leaf runner; the feature plans and scripts are in
  `../Common/tests/features/` (do not copy them here)
- Policy changes go in `../Common/host`; only runtime calls belong in the adapter
- `README.md` (user guide): this document must stay in agreement
  with the scripts on image name, runtime, profile volumes, Docker
  behavior, and the absence of Chrony

## Building

```sh
make build
```

s6-overlay and Node.js are downloaded into `tmp/` and verified by SHA-256
before the image build. The context is staged in `tmp/build-context/` by
`make prepare-context` (allowlist; do not edit it by hand). `tmp/` is git-ignored
build output.

## Runtime scripts

DevBox profile/container lifecycle is managed by the shell scripts in the
repository root:

- `init.sh` (initialize a profile's volumes)
- `backup.sh` (archive both stopped-profile volumes to an explicit `.tar.gz` path)
- `restore.sh` (validate and restore a backup into an absent profile)
- `run.sh` (start a profile container)
- `stop.sh` (stop or remove a profile container)
- `show.sh` (list all created devbox profiles and their SSH/workspace
  mapping)
- `discard.sh` (delete a profile's volumes)
- `code.sh` (open VS Code Remote-SSH against a running profile)
- `ssh.sh` (open an SSH session against a running profile)
- `forward.sh` (start/list/close SSH port forwards into a running profile)
- `shared.sh` (sourced by all of the above, never executed directly; loads the
  Apple Container adapter and the shared `../Common/host/lib` helpers)

See `README.md` for the user-facing usage of each script.

## Testing

Each feature has a test plan (`.md`) and test script (`.sh`) in
`../Common/tests/features/` (index: `FEATURES.md`, applicability:
`applicability.tsv`).

- `make test` runs the prerequisite preflight (Darwin arm64, `container`
  in `PATH`, backend running) and then the full suite via
  `tests/run-tests.sh`.
- The suite requires a clean host: no `devbox-*` containers may exist
  (running or stopped) before it starts.
- Individual features run through the leaf runner, e.g.
  `DEVBOX_TEST_ONLY="F48 F51" bash tests/run-tests.sh` (feature scripts refuse to
  run without the runner's `DEVBOX_TEST_RUNTIME`/`DEVBOX_FRONTEND_DIR`). Tests that
  use `container` stubs run on any host; tests that need the real backend run
  only on the target Mac.

## Secrets and required modes

`../Config/` contains private material (SSH host private key,
authorized keys, root CA). Never print the contents of these files in command output,
commit messages, or tests. Inspect them by checksum and file mode only.

Preserve the required file modes. On disk in this repository:
`Config/authorized_keys` `0400`, `Config/ssh_host_ed25519_key` `0600`, all other
`Config/` files `0644` (enforced when the build context is prepared). In the image,
`Containerfile` enforces:
CA certificate `0444`, `/opt/ssh/authorized_keys` `0400`, SSH private key
`0600`, SSH public key and config `0644`, `/opt/docker/daemon.json` `0444`.
