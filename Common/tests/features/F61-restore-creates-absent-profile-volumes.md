# F61 — restore creates an absent profile from a backup archive

## Purpose

Verify that `restore.sh` validates a backup archive, creates the two volumes
for an absent target profile, and mounts them for extraction.

## Acceptance criteria

- The target home and Docker volumes are created.
- The helper mounts them at `/restore/home` and `/restore/docker`.
- The archive parent directory is bind-mounted for extraction.
- With `-y`, the script skips the confirmation prompt, reports that the
  archive is a default named-volume backup, and reports successful
  restoration of the target profile.
