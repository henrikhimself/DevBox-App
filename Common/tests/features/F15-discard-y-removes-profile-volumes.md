# F15 - discard -y removes profile volumes

## Objective
Verify `discard.sh -y` removes the profile volumes.

## Entry point
`./discard.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./discard.sh ]] || { printf '%s\n' '❌ ./discard.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Ensure profile `tplandiscardy` has both volumes.
2. Run `./discard.sh -y tplandiscardy`.
3. Verify both `devbox-tplandiscardy` and `devbox-tplandiscardy-docker` are removed.
