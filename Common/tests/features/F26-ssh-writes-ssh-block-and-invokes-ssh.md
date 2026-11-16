# F26 - ssh writes the SSH block correctly and invokes ssh with the right arguments

## Objective
Verify `ssh.sh`, for a running profile: writes/replaces exactly that
profile's `Host devbox-<profile>` block in `~/.ssh/devbox_config` (correct
permissions, correct port, idempotent across repeated runs with no
blank-line accumulation, no collateral damage to other profiles' blocks);
and invokes `ssh -t devbox-<profile> "tmux -u new-session -A -s 'devbox-<profile>' -c '<target-path>' bash -l"`
(with `devbox-<profile>:<name>` when `-s <name>` is given).
Never touches the real `~/.ssh/devbox_config` on the host running the test.

## Entry point
`./ssh.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./ssh.sh ]] || { printf '%s\n' '❌ ./ssh.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running fixture container `devbox-tplanssh` with a free port.
2. Pre-seed the scratch `~/.ssh/devbox_config` with two unrelated blocks
   (`devbox-other`, `devbox-tplanssh2`).
3. Run `./ssh.sh -v tplanssh` with `HOME` overridden to a scratch directory and
   a fake `ssh` shim prepended to `PATH` that logs its arguments (`ssh.sh`
   execs into it); verify success and that the shim was invoked with exactly
   `-t devbox-tplanssh "tmux -u new-session -A -s 'devbox-tplanssh' -c '/workspace' bash -l"`.
   Then run `./ssh.sh -v tplanssh -s lint` and verify the shim received the
   named-session remote command
   `tmux -u new-session -A -s 'devbox-tplanssh:lint' -c '/workspace' bash -l`.
4. Verify `~/.ssh` is `700`, `devbox_config` is `600`, the new
   `Host devbox-tplanssh` block with the correct port is present, and the
   two pre-seeded blocks are untouched.
5. Re-run twice more; verify `devbox_config`'s content is byte-identical
   across all three runs.
6. Verify the real `~/.ssh/devbox_config` (this test process's own actual
   `HOME`) is byte-identical before and after the whole test.
