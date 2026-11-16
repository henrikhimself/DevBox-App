# F37 - forward -D -v (no -p) errors clearly when no forwards are active for that profile

## Objective
Verify `forward.sh -D -v <profile>` (bulk-close mode, no `-p`) fails with a
clear message when that profile has no active forwards, without requiring
its container to be running.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh -D -v tplanfwdbulknone` for a profile that has never had
   any forward started.
2. Verify failure with a "No active forwards found for profile
   'tplanfwdbulknone'" message.
