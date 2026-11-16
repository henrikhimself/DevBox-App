# F09 - stop force-remove kept container

## Objective
Verify `stop.sh -D -v <profile>` removes kept container.

## Entry point
`./stop.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./stop.sh ]] || { printf '%s\n' '❌ ./stop.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Create container `devbox-tplankeeprm-keep`.
2. Run `./stop.sh -D -v tplankeeprm`.
3. Verify `devbox-tplankeeprm-keep` no longer exists.
