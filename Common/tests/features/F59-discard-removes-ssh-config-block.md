# F59 - discard removes the ssh config block for the discarded profile

## Objective
Verify `discard.sh` removes the profile's `Host devbox-<profile>` block from
`~/.ssh/devbox_config` when it discards the profile, without touching other
profiles' blocks, without changing the file's permissions, and without
touching the real `~/.ssh/devbox_config`. Also verifies the "no volumes to
discard" gate is unchanged.

## Entry point
`./discard.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./init.sh ]] || { printf '%s\n' '❌ ./init.sh not found (run from the repository root).'; exit 1; }
   [[ -f ./discard.sh ]] || { printf '%s\n' '❌ ./discard.sh not found (run from the repository root).'; exit 1; }
   ```
2. Record a hash of the real `~/.ssh/devbox_config` (if present) to prove
   it is never touched.

## Steps
1. Create a fake HOME and seed its `~/.ssh/devbox_config` with the target
   profile's block (the exact shape `dv::prepare_ssh_alias` writes) plus an
   unrelated `Host devbox-other` block.
2. Initialize the profile `tplandscfg` (volumes only, no container).
3. Run `discard.sh -y tplandscfg` with `HOME` set to the fake HOME.
4. Verify the target `Host devbox-tplandscfg` block (and its `Port 2201`
   body) is gone.
5. Verify the unrelated `Host devbox-other` block (and its `Port 2200`
   body) survives.
6. Verify the config file is still exactly `600`.
7. Verify both profile volumes are removed (core behavior unchanged).
8. Re-run `discard.sh -y tplandscfg`; verify it still fails with the
   "no volumes to discard" error (gate unchanged).
9. Verify the real `~/.ssh/devbox_config` is byte-identical (or still
   absent).
10. Cleanup: remove leftover `tplandscfg` volumes and the fake HOME.
