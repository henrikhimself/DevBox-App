# F04 - run requires initialized profile

## Objective
Verify `run.sh` rejects profiles whose expected volumes are missing.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Ensure profile `tplannoninit` volumes are absent.
2. Run `./run.sh -v tplannoninit /workspace`.
3. Verify failure indicates profile has not been initialized.
