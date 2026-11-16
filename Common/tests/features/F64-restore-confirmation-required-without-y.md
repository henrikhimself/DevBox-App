# F64 — restore confirmation required without -y

## Purpose

Verify that `restore.sh` reports the backup scope and then refuses a
non-interactive restore when `-y` is omitted.

## Acceptance criteria

- The script reports whether the archive is a default or full backup before
  confirmation.
- Without `-y`, a non-interactive invocation fails with a message telling
  the caller to re-run with `-y`.
- The restore helper is never started after the confirmation failure.
