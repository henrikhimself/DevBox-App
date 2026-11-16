# F58 - validate rejects hyphen in names

## Objective
Verify `dv::validate_devbox_name` rejects hyphens in both the profile-name
and session-name labels (the character set is now letters, numbers, and
underscore only; the error message names hyphens explicitly). Hyphens are
banned so profile names can never collide with the internal
`devbox-<profile>` / `devbox-<profile>-keep` container naming. Also a
regression guard that underscored names remain valid.

## Entry point
`./init.sh` and `./ssh.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   [[ -f ./ssh.sh ]] || { printf '%s\n' '❌ ./ssh.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `init.sh bad-name`; verify it fails with the profile-name validation
   message (including the "hyphens are not allowed" hint).
2. Run `ssh.sh -s bad-session` (no running profile needed - the session name
   is validated before profile resolution); verify it fails with the
   session-name validation message (including the hyphen hint).
3. Run `init.sh tplanunderscored`; verify it succeeds (underscore is still
   valid).
4. Cleanup: remove the `tplanunderscored` volumes.
