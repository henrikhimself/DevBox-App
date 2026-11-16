# F51 - run bind-mounts the workspace under /workspace/<project-name> by default

1. Make sure `./init.sh` and `./run.sh` are on present in the repository.
2. Create a workspace directory named `my-project` and run `./run.sh -p 2223 -v tplanwsmount <...>/my-project` (no `-t`) with a fake `container` command in `PATH`.
3. Verify the `container run` invocation includes the bind mount `-v <ws>:/workspace/my-project` and the label `devbox.workspace-target=/workspace/my-project`.
4. Verify the resolved mapping is announced in the output (`Bind-mounting <ws> → /workspace/my-project`).
