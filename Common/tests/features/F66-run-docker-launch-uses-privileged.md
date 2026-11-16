# F66 - run launches the Docker guest with --privileged

Docker Engine only. Apple counterpart: F48.

1. Make sure `./run.sh` is present in the repository.
2. Run `./run.sh -p 2223 -v tplanpriv <tmp-workspace>` with a fake `docker` command in `PATH`.
3. Verify the `container run` invocation includes `--privileged` and `--cap-add ALL` (the in-guest rootless Docker daemon does not start under Docker's default confinement without them).
4. Verify the invocation includes no `--device`, `--security-opt`, `--group-add`, host Docker socket mount, host namespace option, `--sysctl` or `--cap-drop`.
