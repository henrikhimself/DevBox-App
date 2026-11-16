# F17 - run requires workspace for first-time keep create

## Objective
Verify `run.sh -k` still requires a `workspace-path` argument when no kept
container already exists for the profile (i.e. `workspace-path` is only
optional when resuming an existing kept container, not when creating one
for the first time).

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Ensure no `devbox-tplannewkeep` or `devbox-tplannewkeep-keep` container
   exists.
2. Run `./run.sh -k -v tplannewkeep` with no workspace-path argument.
3. Verify failure output indicates workspace-path is required.
