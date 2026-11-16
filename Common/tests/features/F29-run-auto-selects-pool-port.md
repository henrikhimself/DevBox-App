# F29 - run auto-selects a pool port for a new ephemeral profile

## Objective
Verify `run.sh`, when `-p` is omitted for a new (ephemeral) profile, auto-selects
and announces a host SSH port from the default pool (`55000`-`59000`)
instead of failing or requiring a manual port.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Initialize a fresh profile `tplanpoolauto`.
2. Run `./run.sh -v tplanpoolauto <tmpdir>` with `DEVBOX_IMAGE=busybox:latest`
   and no `-p`.
3. Verify the command succeeds and prints an auto-selection message.
4. Extract the announced port and verify it falls within `55000`-`59000`.
