# F57 - show lists init-only profile with status none

## Objective
Verify `show.sh` lists a profile that has been initialized (its
`devbox-<profile>` / `devbox-<profile>-docker` volumes exist) but has no
devbox container: the row shows the profile name, `STATUS` = `none`, and
`-` in `SSH_PORT`, `EXISTING_WORKSPACE`, and `TARGET_PATH`. Also verify the
profile disappears from `show.sh` output once discarded (volumes deleted).

## Entry point
`./show.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./show.sh ]] || { printf '%s\n' '❌ ./show.sh not found (run from the repository root).'; exit 1; }
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Initialize a fresh profile `tplannone` (removing any leftover volumes
   first). No container is ever created for it.
2. Verify the profile's home volume exists after init.
3. Run `./show.sh`.
4. Verify the header row is present.
5. Verify a row `tplannone` / `none` / `-` / `-` / `-` is present.
6. Discard the profile with `discard.sh -y tplannone`.
7. Run `./show.sh` again (tolerating the no-profiles error when no
   other profiles exist on the host) and verify `tplannone` no longer
   appears.
8. Cleanup: remove any leftover `tplannone` volumes.
