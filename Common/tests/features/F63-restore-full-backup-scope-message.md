# F63 — restore reports full-backup scope with -y

## Purpose

Verify that `restore.sh -y` reports a full-backup archive explicitly before
restoring it.

## Acceptance criteria

- The archive manifest records `scope=full`.
- With `-y`, the script skips the confirmation prompt.
- The script reports that the archive is a full backup and restores it
  successfully.
