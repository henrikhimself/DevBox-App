# F18 - run resumes kept container without workspace argument

## Objective
Verify `run.sh -k` resumes an existing stopped kept container successfully
when no `workspace-path` argument is given, since the mount cannot be
changed on resume anyway.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Create a stopped container named `devbox-tplanresume-keep`.
2. Run `./run.sh -k -v tplanresume` with no workspace-path argument.
3. Verify the command succeeds and output indicates the kept container is
   being resumed.
