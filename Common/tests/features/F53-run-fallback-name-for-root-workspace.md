# F53 - root workspace falls back to /workspace/root

1. Make sure `./init.sh` and `./run.sh` are on present in the repository.
2. Run `./run.sh -p 2223 -v tplanwsroot /` (the filesystem root has no usable basename) with a fake `container` command in `PATH`.
3. Verify the `container run` invocation includes `-v /:/workspace/root` and the label `devbox.workspace-target=/workspace/root`.
4. Verify the announcement line reads `Bind-mounting / → /workspace/root`.
