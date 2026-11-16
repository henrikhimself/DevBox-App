# F32 - forward requires a port argument

## Objective
Verify `forward.sh` fails with a clear message when `-p` is omitted, in
either start or close mode.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh` with no arguments at all.
2. Verify failure with a message stating `-p host-port[:container-port]` is
   required.
