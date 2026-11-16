# F62 — backup -f archives the full Docker state

## Purpose

Verify that `backup.sh -f` produces one non-empty `.tar.gz` archive for a
stopped initialized profile and includes the full Docker data tree.

## Acceptance criteria

- The archive has the backup format manifest and the helper is invoked in
  full-backup mode.
- The archive contains both `home/` data and Docker data outside
  `docker/volumes/`.
- The caller-selected output directory is bind-mounted for archive output.
- Helper progress is streamed while the archive is being created.
