# F05 - run requires devbox image

## Objective
Verify `run.sh` fails with a clear message when the required image tag is missing.

## Entry point
`./run.sh` (invoked by path)

## Preflight
1. Run:
   ```sh
   [[ -f ./run.sh ]] || { printf '%s\n' '❌ ./run.sh not found (run from the repository root).'; exit 1; }
   ```

## Steps
1. Initialize profile `tplanimage`.
2. Ensure the DevBox image is absent. The default tag is centralized in `Common/image/tag.txt`; this test overrides it with a nonexistent `DEVBOX_IMAGE` (e.g. `localhost:5000/hj/devbox-does-not-exist:99999`), so the default tag is irrelevant.
3. Run `./run.sh -v tplanimage /workspace`.
4. Verify failure indicates the image must be built first.
