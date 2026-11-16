# F28 - ssh auto-detect and multi-running error

## Objective
Verify `ssh.sh` auto-selects the running profile when `-v` is omitted and
exactly one devbox container is running, and errors clearly when multiple
are running (requiring `-v` to pick one) — mirroring `stop.sh`'s existing
auto-detect behavior via the shared `dv::resolve_running_devbox` helper.

## Entry point
`./ssh.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./ssh.sh ]] || { printf '%s\n' '❌ ./ssh.sh not found (run from the repository root).'; exit 1; }
   ```
2. Ensure no `devbox-*` containers are running.

## Steps
1. Start one running test container `devbox-tplansshauto`.
2. Run `./ssh.sh` with no `-v`, a scratch `HOME`, and a fake `ssh` shim; verify
   it auto-detects and connects to `devbox-tplansshauto`.
3. Start a second running container `devbox-tplansshauto2`.
4. Run `./ssh.sh` with no `-v` again; verify it fails with a "Multiple devbox
   containers found" message naming both profiles.
5. Verify the real `~/.ssh/devbox_config` (this test process's own actual
   `HOME`) is byte-identical before and after.
