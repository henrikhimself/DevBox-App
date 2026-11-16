# F19 - run resume blocked by port conflict with a running profile

## Objective
Verify `run.sh -k` refuses to resume a stopped kept container when its
configured SSH port is already bound by another *running* devbox profile,
with a clear message naming the blocking profile — instead of a raw
Apple Container bind-failure error.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Create a stopped kept container `devbox-tplanportblock-keep` configured
   with a free port (started briefly, then stopped, so the port is free for
   step 2).
2. Start a running container `devbox-tplanportblockother` bound to that
   same port, simulating another profile currently using it.
3. Run `./run.sh -k -v tplanportblock` (no workspace argument).
4. Verify the command fails with a message naming the port and the blocking
   profile (`tplanportblockother`).
