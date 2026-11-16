# F39 - forward -l reports no active forwards when there are none

## Objective
Verify `forward.sh -l` (list mode, no `-v`) succeeds and reports "No active
port forwards." when nothing is currently forwarded anywhere, rather than
treating the empty case as an error.

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
1. Run `./forward.sh -l`.
2. Verify it exits 0 with a "No active port forwards." message.
