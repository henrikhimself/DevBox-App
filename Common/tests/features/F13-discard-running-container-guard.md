# F13 - discard running container guard

## Objective
Verify `discard.sh` refuses to discard profile volumes while matching container is running.

## Entry point
`./discard.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./discard.sh ]] || { printf '%s\n' '❌ ./discard.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Initialize `tplandiscardrun`.
2. Start running container named `devbox-tplandiscardrun`.
3. Run `./discard.sh -y tplandiscardrun`.
4. Verify failure indicates running container must be stopped/removed first.
