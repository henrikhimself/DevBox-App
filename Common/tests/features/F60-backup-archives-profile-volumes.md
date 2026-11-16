# F60 — backup archives the home volume plus Docker named volumes

## Purpose

Verify that `backup.sh` produces one non-empty `.tar.gz` archive for a
stopped initialized profile.

## Acceptance criteria

- The helper mounts `devbox-<profile>` as the home source and
  `devbox-<profile>-docker` as the Docker source.
- The archive has the backup format manifest, contains the `home/` tree and
  Docker named-volume data under `docker/volumes/`, and excludes Docker
  image data.
- The caller-selected output directory is bind-mounted for archive output.
- Helper progress is streamed while the archive is being created, rather than
  being withheld until the helper exits.
