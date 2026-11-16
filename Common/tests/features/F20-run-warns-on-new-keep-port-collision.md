# F20 - run warns (but succeeds) on new keep creation with a colliding port

## Objective
Verify `run.sh -k`, when creating a brand-new kept container, warns (but
does not block) if the chosen/default port already matches another
existing devbox profile's configured port — even if that other profile is
currently stopped — so the user isn't silently set up for a future resume
conflict.

## Entry point
`./init.sh` and `./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Create a stopped kept container `devbox-tplanportwarnexisting-keep`
   configured with a free port, simulating an existing other kept profile.
2. Initialize a brand-new profile `tplanportwarnnew` via `./init.sh`.
3. Run `./run.sh -k -v tplanportwarnnew -p <same port> <workspace>` with
   `DEVBOX_IMAGE=busybox:latest`.
4. Verify the command succeeds (exit 0) and the output contains a warning
   naming the port and the colliding profile (`tplanportwarnexisting`).
