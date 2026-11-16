# F35 - forward -D errors clearly when no forward is active for the profile

## Objective
Verify `forward.sh -D -v <profile>` fails with a clear message when no
forward is active for that profile/port, and that this works without
requiring the profile's container to be running (a forward's lifecycle is
independent of container state).

## Entry point
`./forward.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./forward.sh ]] || { printf '%s\n' '❌ ./forward.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Run `./forward.sh -D -v tplanfwdnoneactive -p 54321:54321` for a profile
   that has never had a forward started, with no running container
   required.
2. Verify failure with a "No active forward found for profile
   'tplanfwdnoneactive' on 54321:54321" message.
