# F31 - run fails clearly when the port pool is exhausted

## Objective
Verify `run.sh` fails with a clear message (instead of attempting a colliding
`container run`) when every port in the configured pool is already used by
another `devbox-*` profile, and suggests `-p` as the way out.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running fixture container `devbox-tplanpoolexhaustexisting` bound
   to a free port, `P`.
2. Run `./run.sh -v tplanpoolexhaust <tmpdir>` with both
   `DEVBOX_PORT_POOL_START` and `DEVBOX_PORT_POOL_END` set to `P` (a
   single-port pool, already occupied) and no `-p`.
3. Verify the command fails (non-zero exit) with the "No available SSH host
   port in the pool" message naming the range `P-P`.
