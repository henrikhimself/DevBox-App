# F36 - forward -D without -v errors clearly when no profile has that forward active

## Objective
Verify `forward.sh -D` (no `-v`) fails with a clear message naming "any
profile" when it can't auto-detect a profile because no active forward
exists anywhere for the given port pair.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh -D -p 54322:54322` with no `-v`, where no profile has an
   active forward on that port pair.
2. Verify failure with a "No active forward found on 54322:54322 for any
   profile" message.
