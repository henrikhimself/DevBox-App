# F34 - forward requires a running profile to start

## Objective
Verify `forward.sh` (starting a forward, no `-D`) fails with a clear
message when no devbox container is running for the given profile, and
never touches the real `~/.ssh/devbox_config` on the host running the test.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh -v tplanfwdnorun -p 8443:443` with `HOME` overridden to a
   fresh scratch directory (never the real `HOME`), for a profile with no
   running container.
2. Verify failure with a message indicating no running devbox exists for
   that profile.
3. Verify the real `~/.ssh/devbox_config` (this test process's own actual
   `HOME`) is byte-identical before and after.
