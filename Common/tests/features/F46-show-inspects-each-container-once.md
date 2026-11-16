# F46 - show inspects each container once

1. Run `./show.sh` with a fake `container` binary (via `PATH`) and `CONTAINER_CMD=container`.
2. Fake runtime lists exactly two `devbox-*` containers.
3. Verify `./show.sh` output includes expected rows for both containers.
4. Verify fake runtime log contains exactly two `inspect` calls (one per container).
