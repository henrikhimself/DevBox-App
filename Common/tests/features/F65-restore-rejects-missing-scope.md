# F65 — restore rejects archives missing scope metadata

## Purpose

Verify that `restore.sh` rejects an archive whose manifest omits the required
`scope=` line.

## Acceptance criteria

- The script fails before creating volumes or starting the restore helper.
- The failure message clearly says the archive is missing required scope
  metadata.
