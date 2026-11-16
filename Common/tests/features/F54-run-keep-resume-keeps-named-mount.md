# F54 - resuming a kept container keeps its original named workspace mount

1. Make sure `./init.sh` and `./run.sh` are on present in the repository.
2. Initialize a profile and create a kept container with `./run.sh -k -p <port> -v tplanwskeep <...>/my-project`; the busybox fixture exits immediately, but the kept container (no `--rm`) lingers stopped.
3. Verify the container's mounts include the pair `<ws> -> /workspace/my-project`.
4. Stop the container, then resume with `./run.sh -k -v tplanwskeep` (no workspace argument).
5. Verify the resume message is printed and the mount pair is still present (workspace-path and `-t` are ignored on resume).
