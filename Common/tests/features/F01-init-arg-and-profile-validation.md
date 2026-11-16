# F01 - init arg and profile validation

## Objective
Verify `init.sh` defaults to the `home` profile when no argument is given,
rejects extra arguments, and rejects invalid profile names.

## Entry point
`./init.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./init.sh` with no args.
   - Verify it succeeds and initializes the `home` profile
     (`📦 Initializing profile: home` and the ✅ success marker).
2. Run `./init.sh alpha beta`.
   - Verify it fails with the `Usage:` output.
3. Run `./init.sh invalid*name`.
   - Verify it fails with the profile-name validation output
     (`must start with an alphanumeric`).
