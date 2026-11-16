# F08 - stop with profile selection

## Objective
Verify `stop.sh -v <profile>` stops the selected running profile.

## Entry point
`./stop.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./stop.sh ]] || { printf '%s\n' '❌ ./stop.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start `devbox-tplanvsel` running.
2. Run `./stop.sh -v tplanvsel`.
3. Verify container is no longer running.
