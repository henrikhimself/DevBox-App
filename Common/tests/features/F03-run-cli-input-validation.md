# F03 - run CLI input validation

## Objective
Verify `run.sh` validates workspace path and option value formats.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./run.sh` with no args.
2. Run `./run.sh /path/that/does/not/exist`.
3. Run `./run.sh -m 0 /workspace`.
4. Run `./run.sh -c 0 /workspace`.
5. Run `./run.sh -p 70000 /workspace`.
6. Run `./run.sh -t relative/path /workspace`.
7. Verify each invalid invocation fails with explicit validation output.
