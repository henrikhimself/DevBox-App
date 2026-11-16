# F02 - init volume initialization idempotent

## Objective
Verify `init.sh` creates profile volumes and can run again without failing.

## Entry point
`./init.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./init.sh tplaninit`.
2. Inspect volumes `devbox-tplaninit` and `devbox-tplaninit-docker`.
3. Re-run `./init.sh tplaninit`.
4. Verify success output both times.
