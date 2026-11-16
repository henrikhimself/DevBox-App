# F07 - stop auto detect and multi-running behavior

## Objective
Verify `stop.sh` auto-selects when exactly one devbox container is running and errors when multiple are running.

## Entry point
`./stop.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./stop.sh ]] || { printf '%s\n' '❌ ./stop.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start one running test container `devbox-tplanstop1`.
2. Run `./stop.sh` and verify it stops that container.
3. Start two running containers `devbox-tplanstop1` and `devbox-tplanstop2`.
4. Run `./stop.sh` and verify multi-profile error requiring `-v`.
