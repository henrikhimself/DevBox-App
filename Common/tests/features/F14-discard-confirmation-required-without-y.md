# F14 - discard confirmation required without -y

## Objective
Verify `discard.sh` requires confirmation for non-interactive invocation when `-y` is omitted.

## Entry point
`./discard.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./discard.sh ]] || { printf '%s\n' '❌ ./discard.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Ensure profile `tplandiscardask` has existing volumes.
2. Run `./discard.sh tplandiscardask` in non-interactive mode.
3. Verify failure output asks to re-run with `-y`.
