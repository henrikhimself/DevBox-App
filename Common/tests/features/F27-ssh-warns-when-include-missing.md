# F27 - ssh warns when ~/.ssh/config doesn't Include devbox_config

## Objective
Verify `ssh.sh` prints a non-blocking warning (command still succeeds) when
the user's `~/.ssh/config` doesn't appear to `Include ~/.ssh/devbox_config`,
and suggests the exact line to add.

## Entry point
`./ssh.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./ssh.sh ]] || { printf '%s\n' '❌ ./ssh.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running fixture container `devbox-tplansshinc`.
2. Use a scratch `HOME` (never the real one) with no `~/.ssh/config` at
   all, plus a fake `ssh` shim in `PATH` so the run can succeed without a
   real ssh session.
3. Run `./ssh.sh -v tplansshinc`.
4. Verify the command succeeds (exit 0) and the output contains the
   missing-Include warning and the suggested `Include ~/.ssh/devbox_config`
   line.
5. Verify the real `~/.ssh/devbox_config` (this test process's own actual
   `HOME`) is byte-identical before and after.
