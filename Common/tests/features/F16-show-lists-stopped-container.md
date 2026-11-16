# F16 - show lists stopped container

## Objective
Verify `show.sh` lists a stopped (not running) `devbox-*` container, with
`STATUS` reading `stopped`, and with `SSH_PORT`/`EXISTING_WORKSPACE`/
`TARGET_PATH` all resolving correctly even though the container isn't
running. `dv::container_ssh_host_port` reads the published-port config from
the Apple Container inspect JSON (`.configuration.publishedPorts[]`, a
static creation-time config verified to persist identically before and
after `container stop`), and mount info persists regardless of run state
too.

## Entry point
`./show.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./show.sh ]] || { printf '%s\n' '❌ ./show.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running container `devbox-tplanstopped` with a published port and
   a temp-directory bind mount, then stop it (do not remove it).
2. Verify the fixture is actually stopped (not running) before trusting
   `show.sh`'s output.
3. Run `./show.sh`.
4. Verify output contains the header row (with `STATUS`) and a row for
   `tplanstopped` with `STATUS` = `stopped`, the real configured `SSH_PORT`,
   and the expected workspace/target path.
