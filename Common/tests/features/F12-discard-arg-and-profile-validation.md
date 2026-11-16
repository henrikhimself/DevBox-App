# F12 - discard arg and profile validation

## Objective
Verify `discard.sh` requires a profile argument and validates profile name format.

## Entry point
`./discard.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./discard.sh ]] || { printf '%s\n' '❌ ./discard.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./discard.sh` with no args.
2. Run `./discard.sh bad*name`.
3. Verify each run fails with usage/validation output.
