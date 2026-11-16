# F48 - run grants the full capability set

Apple Container only. Docker counterpart: F66.

1. Make sure `./run.sh` is on present in the repository.
2. Run `./run.sh -p 2223 -v tplancaps <tmp-workspace>` with a fake `container` command in `PATH`.
3. Verify the `container run` invocation includes `--cap-add ALL` (granted for in-container hostname setting and the in-guest rootless Docker daemon).
4. Verify the `container run` invocation does NOT include `--privileged`, `--group-add`, or a host Docker socket mount (`/var/run/docker.sock`).
