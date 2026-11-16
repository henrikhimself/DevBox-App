# F06 - run blocks ephemeral when kept exists

## Objective
Verify non-keep runs are blocked when a kept container exists for the same profile.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Create a stopped container named `devbox-tplankeep-keep`.
2. Run `./run.sh -v tplankeep /workspace` (without `-k`).
3. Verify failure says kept container must be resumed with `-k` or removed via stop `-D`.
