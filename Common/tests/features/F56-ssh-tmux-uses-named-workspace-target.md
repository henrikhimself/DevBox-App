# F56 - ssh starts the tmux session in the named workspace target

1. Make sure `./ssh.sh` is on present in the repository.
2. Start a running fixture container `devbox-tplanwsssh` exactly as `run.sh` now creates it for a default (no `-t`) run: label `devbox.workspace-target=/workspace/my-project` and mount `<ws>:/workspace/my-project`.
3. Run `./ssh.sh -v tplanwsssh` with a fake `ssh` shim in `PATH` (and a scratch `HOME`) to capture the remote command.
4. Verify the tmux remote command is `tmux -u new-session -A -s 'devbox-tplanwsssh' -c '/workspace/my-project' bash -l`.
5. Verify the real `~/.ssh/devbox_config` is untouched.
