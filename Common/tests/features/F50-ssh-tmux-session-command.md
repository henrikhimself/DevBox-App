# F50 - ssh lands in a fixed per-profile tmux session; -s selects a named session

## Objective
Verify `ssh.sh` connects through tmux: the SSH remote command is always
`tmux -u new-session -A -s 'devbox-<profile>' -c '<target-path>' bash -l`
(create-or-attach to the fixed per-profile session, so reconnecting attaches
to the same session), `-s <name>` targets the named extra session
`devbox-<profile>:<name>`, and the shared name rule rejects `.` and `:` in
both session names and profile names (tmux forbids both; the tightened
profile-name rule uses the same character class). Never touches the real
`~/.ssh/devbox_config` on the host running the test.

## Entry point
`./ssh.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./ssh.sh ]] || { printf '%s\n' '❌ ./ssh.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running fixture container `devbox-tpltm` with a free port.
2. Run `./ssh.sh -v tpltm` with `HOME` overridden to a scratch directory and a
   fake `ssh` shim prepended to `PATH` that logs its arguments (`ssh.sh`
   execs into it); verify the shim received exactly
   `-t devbox-tpltm "tmux -u new-session -A -s 'devbox-tpltm' -c '/workspace' bash -l"`
   and that the connect message names the tmux session.
3. Re-run; verify the remote command is byte-identical (same fixed session,
   i.e. attach rather than recreate).
4. Run `./ssh.sh -v tpltm -s build`; verify the shim received the named-session
   remote command
   `tmux -u new-session -A -s 'devbox-tpltm:build' -c '/workspace' bash -l`.
5. Run `./ssh.sh -v tpltm -s a.b` and `./ssh.sh -v tpltm -s a:b`; verify both fail
   with the session-name character-rule error (dots and colons rejected).
6. Run `./ssh.sh -v tpltm.keep`; verify it fails with the profile-name
   character-rule error (tightened rule: dots are no longer allowed in
   profile names).
7. Verify the real `~/.ssh/devbox_config` (this test process's own actual
   `HOME`) is byte-identical before and after the whole test.
