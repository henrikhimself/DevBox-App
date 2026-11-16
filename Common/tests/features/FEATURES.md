# Management script feature list

This is the current feature inventory for:

- `init.sh`
- `backup.sh`
- `restore.sh`
- `run.sh`
- `show.sh`
- `stop.sh`
- `discard.sh`
- `code.sh`
- `ssh.sh`
- `forward.sh`

Each feature has a dedicated test plan file in this directory. The suite is shared by
both runtimes: `applicability.tsv` records, per feature, whether it is common or
Apple-specific and whether it needs the real runtime or a stub (stub tests run on any
host).

| ID | Script | Feature | Plan |
| --- | --- | --- | --- |
| F01 | init | Defaults to `home` profile when no argument, rejects extra args, and validates name format | `F01-init-arg-and-profile-validation.md` |
| F02 | init | Initializes profile volumes and can be safely re-run | `F02-init-volume-initialization-idempotent.md` |
| F03 | run | Validates CLI options and workspace argument shape | `F03-run-cli-input-validation.md` |
| F04 | run | Requires initialized profile volumes before running | `F04-run-requires-initialized-profile.md` |
| F05 | run | Requires the frontend's image (image tag is centralized in `Common/image/tag.txt`; the frontend image is `localhost:5000/hj/devbox-apple` (Apple Container) or `localhost:5000/hj/devbox-docker` (Docker); `DEVBOX_IMAGE` overrides to exist | `F05-run-requires-devbox-image.md` |
| F06 | run | Blocks ephemeral run when kept container exists for same profile | `F06-run-blocks-ephemeral-when-kept-exists.md` |
| F07 | stop | Auto-detects single running profile; errors when multiple/no running profiles | `F07-stop-auto-detect-and-multi-running-error.md` |
| F08 | stop | Stops the selected running profile using `-v` | `F08-stop-with-profile-selection.md` |
| F09 | stop | `-D -v` force-removes kept container | `F09-stop-force-remove-kept-container.md` |
| F11 | show | Lists running devbox profile with status/SSH port/workspace/target path | `F11-show-lists-profile-and-mount-details.md` |
| F12 | discard | Requires profile argument and rejects invalid profile names | `F12-discard-arg-and-profile-validation.md` |
| F13 | discard | Refuses discard when matching profile container is running | `F13-discard-running-container-guard.md` |
| F14 | discard | Requires interactive confirmation when `-y` is not provided | `F14-discard-confirmation-required-without-y.md` |
| F15 | discard | `-y` discards existing profile volumes | `F15-discard-y-removes-profile-volumes.md` |
| F16 | show | Lists a stopped devbox profile with STATUS=stopped | `F16-show-lists-stopped-container.md` |
| F17 | run | `-k` still requires workspace-path when no kept container exists yet | `F17-run-requires-workspace-for-new-keep.md` |
| F18 | run | `-k` resumes an existing kept container without a workspace-path argument | `F18-run-resumes-kept-container-without-workspace.md` |
| F19 | run | `-k` resume is blocked with a clear message when its port conflicts with another running profile | `F19-run-resume-blocked-by-port-conflict.md` |
| F20 | run | `-k` warns (but still succeeds) when creating a new kept profile whose port collides with an existing one | `F20-run-warns-on-new-keep-port-collision.md` |
| F21 | code | Requires a running devbox container for the given profile | `F21-code-requires-running-profile.md` |
| F22 | code | Writes/replaces the profile's `~/.ssh/devbox_config` Host block idempotently and invokes `code` with the correct `--folder-uri` | `F22-code-writes-ssh-block-and-invokes-code.md` |
| F23 | code | Warns (non-blocking) when `~/.ssh/config` doesn't Include `devbox_config` | `F23-code-warns-when-include-missing.md` |
| F24 | code | Auto-detects single running profile when `-v` is omitted; errors when multiple are running | `F24-code-auto-detect-and-multi-running-error.md` |
| F25 | ssh | Requires a running devbox container for the given profile | `F25-ssh-requires-running-profile.md` |
| F26 | ssh | Writes/replaces the profile's `~/.ssh/devbox_config` Host block idempotently and invokes `ssh` with the correct alias/command | `F26-ssh-writes-ssh-block-and-invokes-ssh.md` |
| F27 | ssh | Warns (non-blocking) when `~/.ssh/config` doesn't Include `devbox_config` | `F27-ssh-warns-when-include-missing.md` |
| F28 | ssh | Auto-detects single running profile when `-v` is omitted; errors when multiple are running | `F28-ssh-auto-detect-and-multi-running-error.md` |
| F29 | run | Auto-selects a host port from the default pool (55000-59000) for a new profile when `-p` is omitted | `F29-run-auto-selects-pool-port.md` |
| F30 | run | Auto-selection skips a port already used by another devbox profile and picks the next pool port | `F30-run-auto-select-avoids-existing-port-conflict.md` |
| F31 | run | Fails clearly (suggesting `-p`) when every port in the pool is already in use | `F31-run-fails-when-pool-exhausted.md` |
| F32 | forward | Requires `-p host-port[:container-port]` | `F32-forward-requires-port-argument.md` |
| F33 | forward | Validates `-p` port syntax (non-numeric, out of range, bad container-port) | `F33-forward-cli-port-syntax-validation.md` |
| F34 | forward | Requires a running devbox container for the given profile to start a forward | `F34-forward-requires-running-profile.md` |
| F35 | forward | `-D -v` errors clearly when no forward is active for that profile/port | `F35-forward-close-with-nothing-active-errors.md` |
| F36 | forward | `-D` without `-v` errors clearly ("for any profile") when nothing matches | `F36-forward-close-without-v-and-no-matches-errors.md` |
| F37 | forward | `-D -v` (no `-p`, bulk-close) errors clearly when that profile has no active forwards | `F37-forward-bulk-close-with-v-errors-when-none-active.md` |
| F38 | forward | `-D` (no `-p`, no `-v`, bulk-close) errors clearly when no forwards are active anywhere | `F38-forward-bulk-close-without-v-errors-when-none-active.md` |
| F39 | forward | `-l` reports "No active port forwards." when there are none | `F39-forward-list-with-nothing-active.md` |
| F40 | forward | `-l -v` reports "No active port forwards for profile" when that profile has none | `F40-forward-list-scoped-with-nothing-active.md` |
| F41 | forward | `-l` is mutually exclusive with `-p`/`-D` | `F41-forward-list-mutually-exclusive-with-p-or-D.md` |
| F45 | forward | `./forward.sh` passes `IdentityFile` options only for key files that actually exist/readable in `~/.ssh` | `F45-forward-identityfile-only-for-existing-keys.md` |
| F46 | show | `./show.sh` performs one inspect per devbox container while still rendering complete rows | `F46-show-inspects-each-container-once.md` |
| F48 | run | Apple Container only: grants the full capability set (`--cap-add ALL`) for in-container hostname setting and the in-guest rootless Docker daemon, without `--privileged`, `--group-add`, or a host Docker socket mount | `F48-run-grants-full-capabilities.md` |
| F50 | ssh | Lands in a fixed per-profile tmux session; `-s` selects a named session; the shared name rule rejects dots and colons | `F50-ssh-tmux-session-command.md` |
| F51 | run | Without `-t`, the workspace is bind-mounted at `/workspace/<project-name>` (basename of the workspace directory) and recorded in the `devbox.workspace-target` label | `F51-run-mounts-under-default-workspace-project-name.md` |
| F52 | run | An explicit `-t` keeps the exact-destination behavior (no project-name subdirectory) | `F52-run-keeps-exact-destination-with-explicit-t.md` |
| F53 | run | A workspace of the filesystem root falls back to the name `root` (`/workspace/root`) | `F53-run-fallback-name-for-root-workspace.md` |
| F54 | run | Resuming a kept container keeps its original named workspace mount (workspace-path and `-t` ignored on resume) | `F54-run-keep-resume-keeps-named-mount.md` |
| F55 | show | Lists a named workspace target (`/workspace/<project-name>`) in the `TARGET_PATH` column | `F55-show-displays-named-target.md` |
| F56 | ssh | Starts the tmux session in the named workspace target recorded by the `devbox.workspace-target` label | `F56-ssh-tmux-uses-named-workspace-target.md` |
| F57 | show | Lists an initialized profile that has no container with status `none` | `F57-show-lists-init-only-profile.md` |
| F58 | validate | Rejects hyphens in profile and session names | `F58-validate-rejects-hyphen.md` |
| F59 | discard | Removes the discarded profile's `Host devbox-<profile>` block from the script-owned SSH config | `F59-discard-removes-ssh-config-block.md` |
| F60 | backup | Archives the home volume plus Docker named volumes into one manifest `.tar.gz` file | `F60-backup-archives-profile-volumes.md` |
| F61 | restore | With `-y`, creates an absent profile's two volumes, reports default-backup scope, and extracts a validated backup archive | `F61-restore-creates-absent-profile-volumes.md` |
| F62 | backup | With `-f`, archives the home volume plus the full Docker state into one manifest `.tar.gz` file | `F62-backup-full-archives-docker-state.md` |
| F63 | restore | With `-y`, reports full-backup scope and restores a validated archive | `F63-restore-full-backup-scope-message.md` |
| F64 | restore | Requires confirmation when `-y` is not provided and reports the backup scope first | `F64-restore-confirmation-required-without-y.md` |
| F65 | restore | Rejects backup archives whose manifest omits the required `scope=` line | `F65-restore-rejects-missing-scope.md` |
| F66 | run | Docker Engine only: launches with exactly `--privileged --cap-add ALL` (no explicit devices or security options, no host Docker socket) | `F66-run-docker-launch-uses-privileged.md` |
