# F55 - show displays a named workspace target in TARGET_PATH

1. Make sure `./show.sh` is on present in the repository.
2. Start a running fixture container `devbox-tplanwsnamed` exactly as `run.sh` now creates it for a default (no `-t`) run: label `devbox.workspace-target=/workspace/my-project` and mount `<ws>:/workspace/my-project`.
3. Run `./show.sh` and verify the row for profile `tplanwsnamed` shows the `TARGET_PATH` column as `/workspace/my-project` and the workspace source as `<ws>`.
