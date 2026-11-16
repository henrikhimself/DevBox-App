# F41 - forward -l is mutually exclusive with -p and -D

## Objective
Verify `forward.sh -l` fails with usage when combined with `-p` or `-D`,
since listing can't be combined with starting or closing a forward in the
same invocation.

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh -l -p 443`; verify failure with usage output.
2. Run `./forward.sh -l -D`; verify failure with usage output.
