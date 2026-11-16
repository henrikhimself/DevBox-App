# F40 - forward -l -v reports no active forwards for a profile with none

## Objective
Verify `forward.sh -l -v <profile>` succeeds and reports "No active port
forwards for profile '<profile>'." when that profile has no active
forwards, without requiring its container to be running.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh -l -v tplanfwdlistnone` for a profile that has never had
   any forward started.
2. Verify it exits 0 with a "No active port forwards for profile
   'tplanfwdlistnone'." message.
