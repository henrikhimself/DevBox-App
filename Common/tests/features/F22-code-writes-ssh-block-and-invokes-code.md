# F22 - code writes the SSH block correctly and invokes code with the right arguments

## Objective
Verify `code.sh`, for a running profile: fails clearly when the `code`
CLI isn't in `PATH`; otherwise writes/replaces exactly that profile's
`Host devbox-<profile>` block in `~/.ssh/devbox_config` (correct
permissions, correct port, idempotent across repeated runs with no
blank-line accumulation, no collateral damage to other profiles' blocks);
and invokes `code --folder-uri vscode-remote://ssh-remote+devbox-<profile><target-path>`.
Never touches the real `~/.ssh/devbox_config` on the host running the test.

## Entry point
`./code.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./code.sh ]] || { printf '%s\n' '❌ ./code.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running fixture container `devbox-tplancode` with a free port.
2. Run `./code.sh -v tplancode` with `HOME` overridden to a scratch
   directory and a minimal `PATH` known to lack `code`; verify failure with
   a "code not found" message.
3. Pre-seed the scratch `~/.ssh/devbox_config` with two unrelated blocks
   (`devbox-other`, `devbox-tplancode2`).
4. Run `./code.sh -v tplancode` again with a fake `code` shim prepended
   to `PATH` that logs its arguments; verify success and that the shim was
   invoked with exactly `--folder-uri vscode-remote://ssh-remote+devbox-tplancode/workspace`.
5. Verify `~/.ssh` is `700`, `devbox_config` is `600`, the new
   `Host devbox-tplancode` block with the correct port is present, and the
   two pre-seeded blocks are untouched.
6. Re-run twice more; verify `devbox_config`'s content is byte-identical
   across all three runs.
7. Verify the real `~/.ssh/devbox_config` (this test process's own actual
   `HOME`) is byte-identical before and after the whole test.
