# F33 - forward CLI port syntax validation

## Objective
Verify `forward.sh` rejects malformed `-p` values (non-numeric, out of
range, and a bad `container-port` in the `host:container` form) with a
clear message, for both the single-port and `host:container` forms.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh -p abc`; verify failure with the port-format error.
2. Run `./forward.sh -p 70000`; verify failure with the same port-range error.
3. Run `./forward.sh -p 8443:notaport`; verify failure with the same error for
   the invalid `container-port` half.
