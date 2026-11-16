# F30 - run auto-select avoids a port already used by another devbox profile

## Objective
Verify `run.sh`'s pool-based auto-selection skips a port already reserved by
another `devbox-*` profile and picks the next available pool port instead.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start a running fixture container `devbox-tplanpoolavoidexisting` bound
   to a free port, `P`.
2. Initialize a fresh profile `tplanpoolavoid`.
3. Run `./run.sh -v tplanpoolavoid <tmpdir>` with `DEVBOX_PORT_POOL_START=P`
   and `DEVBOX_PORT_POOL_END=P+1` (a narrow, deterministic 2-port pool) and
   no `-p`.
4. Verify the command succeeds and the auto-selection message announces
   port `P+1`, not the occupied `P`.
