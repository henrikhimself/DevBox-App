# F11 - show lists profile and mount details

## Objective
Verify `show.sh` reports profile, status, SSH host port, existing workspace source, and target path for a running devbox-named container. The `STATUS` column must read `running`.

## Entry point
`./show.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./show.sh ]] || { printf '%s\n' '❌ ./show.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Start running container `devbox-tplanshow` with `-p 22345:2222` and mount `/workspace:/workspace`.
2. Run `./show.sh`.
3. Verify output contains row for `tplanshow` with expected SSH port and workspace mapping.
