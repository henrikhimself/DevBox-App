# F38 - forward -D (no -p, no -v) errors clearly when no forwards are active anywhere

## Objective
Verify `forward.sh -D` (bulk-close mode, no `-p`, no `-v`) fails with a
clear message when no forwards are active for any profile.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```
2. Ensure no forward control sockets exist under
   `/tmp/devbox-forwards-$(id -u)` (this test depends on a host-wide clean
   state, unlike other `forward.sh` tests which use a unique profile name).

## Steps
1. Run `./forward.sh -D` with no `-p` and no `-v`.
2. Verify failure with a "No active forwards found." message.
