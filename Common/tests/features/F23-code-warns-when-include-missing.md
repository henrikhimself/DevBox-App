# F23 - code warns when ~/.ssh/config doesn't Include devbox_config

## Objective
Verify `code.sh` prints a non-blocking warning (command still succeeds)
when the user's `~/.ssh/config` doesn't appear to `Include
~/.ssh/devbox_config`, and suggests the exact line to add.

## Entry point
`./code.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./code.sh ]] || { printf '%s\n' '❌ ./code.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running fixture container `devbox-tplancodeinc`.
2. Use a scratch `HOME` (never the real one) with no `~/.ssh/config` at
   all, plus a fake `code` shim in `PATH` so the run can succeed without
   real VS Code installed.
3. Run `./code.sh -v tplancodeinc`.
4. Verify the command succeeds (exit 0) and the output contains the
   missing-Include warning and the suggested `Include ~/.ssh/devbox_config`
   line.
5. Verify the real `~/.ssh/devbox_config` (this test process's own actual
   `HOME`) is byte-identical before and after.
