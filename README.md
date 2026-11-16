# DevBox

A development environment that runs as a container and is used over SSH
(port 2222): a persistent per-profile home directory, a bind-mounted workspace
and an in-guest rootless Docker daemon.

There are two variants. They share one image definition, one set of lifecycle
commands and one host-state layout, and differ only in the runtime they drive:

| Variant | Host | Runtime | Image tag | Guide |
| --- | --- | --- | --- | --- |
| [`AppleContainer/`](AppleContainer/README.md) | Apple-silicon macOS (Darwin arm64) | Apple Container | `localhost:5000/hj/devbox-apple (tag in `Common/image/tag.txt`)` | [README](AppleContainer/README.md) |
| [`Docker/`](Docker/README.md) | native Linux amd64 | Rootful Docker Engine (Unix socket) | `localhost:5000/hj/devbox-docker (tag in `Common/image/tag.txt`)` | [README](Docker/README.md) |

The split is deliberate: each variant builds and runs natively on its own host
(arm64 on macOS, amd64 on Linux). There is no cross-architecture build, no
automatic runtime selection. The shared requirements are in [`SPEC.md`](SPEC.md).

## Building

Run from the variant's directory (`make -C AppleContainer build`, `make -C
Docker build`).

## Secrets

`Config/` contains private material (SSH host key, authorized keys, root CA).
Modes (on disk `authorized_keys` `0400`, host key `0600`, the rest `0644`)
and checksums are verified and enforced when the context is prepared.

## Profiles and their volumes

A **profile** is an independent DevBox: its own container, its own home
directory, its own in-guest Docker state, and its own workspace mapping. The
default profile name is `home`.

Initializing a profile creates two persistent named volumes:

| Volume | Mounted at | Holds |
| --- | --- | --- |
| `devbox-<profile>` | `/home` | Your home directory and anything else installed under `/home` |
| `devbox-<profile>-docker` | `/data/docker` | The in-guest Docker daemon's state (images, containers, volumes, build cache) |

```sh
./init.sh                 # initialize the default profile 'home'
./init.sh work            # initialize a profile named 'work'
./show.sh                 # list all profiles: status, SSH port, workspace, mount target
```

`show.sh` lists every initialized profile, with or without a running
container.

## Running a container

```sh
./run.sh /path/to/your/project
```

This starts (or resumes, with `-k`) the profile's container with:

- the profile's `devbox-<profile>` volume at `/home`
- the profile's `devbox-<profile>-docker` volume at `/data/docker`
- your workspace bind-mounted at `/workspace/<project-name>` (the workspace
  directory's basename; a workspace of `/` mounts at `/workspace/root`)
- the SSH port inside the container (fixed at `2222`) published on an
  available host port
- `--cap-add ALL`, which the in-guest rootless Docker daemon and the
  in-container hostname setting require

Options:

```
  -m memory-gb     Memory in GB (default: 2)
  -c cpu-cores     CPU cores (default: one less than total host cores)
  -p host-port     Fixed host SSH port (default: auto-selected from 55000-59000)
  -v profile-name  Profile name (default: home)
  -t target-path   Exact in-container mount point for the workspace
                   (default: /workspace/<project-name>)
  -k               Keep the container after it stops, and resume it as-is
                   on the next `run.sh -k` for the same profile
```

The workspace argument is required, except when resuming a kept container
with `-k` (where it is ignored).

## SSH, VS Code, and tmux

With the container running:

```sh
./ssh.sh                 # SSH in; lands in the profile's tmux session
./code.sh                # open VS Code Remote-SSH against the profile
```

Both auto-detect the profile when exactly one is running; otherwise pass
`-v <profile>`.

`ssh.sh` lands every connection in a per-profile `tmux` session
(`devbox-<profile>`) in your workspace directory: it is created if missing,
attached if present, so reconnecting resumes exactly where you left off.
Detach with `Ctrl-b d` (the session keeps running) and re-run `ssh.sh` to
attach again. Use `-s <session-name>` for a named second session, one
terminal per session.

## Port forwarding

`forward.sh` tunnels a port from a service on localhost *inside* the
container to a port on your Mac, over the profile's SSH connection:

```sh
./forward.sh -p 8080                 # host 8080 -> container 8080
./forward.sh -p 9090:8080            # host 9090 -> container 8080
./forward.sh -l                      # list active forwards
./forward.sh -D -p 8080              # close the forward on host port 8080
./forward.sh -D -y                   # close all forwards (with -v: just one profile)
```

Never run `forward.sh` with `sudo`. For a privileged host port (<1024) it
prompts for sudo itself.

## Kept containers

By default the container is removed when it stops (`--rm`): your volumes
persist, container-level state (e.g. running daemons you started by hand)
does not.

Run with `-k` to keep the container:

```sh
./run.sh -k /path/to/project
```

After the container stops, it is kept on disk with all its state. Running
`./run.sh -k -v <profile>` again resumes the kept container as-is, ignoring
`workspace-path` and `-m`/`-c`/`-p`/`-t`. To delete a kept container, use
`./stop.sh -D -v <profile>`.

## Backing up and restoring profile data

`backup.sh` makes one gzip-compressed, restorable archive from a stopped
profile's `/home` volume. By default it also includes any Docker named
volumes stored under `/data/docker/volumes`, while excluding downloaded
Docker images, container layers, and build cache. Pass `-f` for a full
backup of `/data/docker` as well. The workspace bind mount and a kept
container's filesystem layer are never included.

```sh
./backup.sh work /path/to/work-backup.tar.gz
./backup.sh -f work /path/to/work-full-backup.tar.gz
```

The output path is explicit, must end in `.tar.gz`, and must not already
exist. `backup.sh` refuses a profile with either a normal or kept container
running, so the volume contents are consistent. It streams helper output and
reports archive progress every 5 MiB; large named-volume or full Docker
backups can take time to compress.

Restore into an absent profile only:

```sh
./restore.sh restored-work /path/to/work-backup.tar.gz
./restore.sh -y restored-work /path/to/work-backup.tar.gz
```

`restore.sh` validates the backup, and asks for a `yes`/`no` confirmation before
it creates any target volumes. Pass `-y` to skip that confirmation.

Discard an existing target profile deliberately before restoring it.

## Stopping and cleanup

```sh
./stop.sh                      # stop the running container
./stop.sh -v <profile>         # stop a specific profile's container
./stop.sh -D -v <profile>      # also remove a kept container
./discard.sh <profile>         # delete the profile's two volumes (asks first; -y to skip)
```

Stopping never touches volumes. `discard.sh` deletes everything a profile
owns (home data and in-guest Docker state) — it is the destructive step.

## First-login installers

On the first interactive SSH login to a profile, the image offers to install
developer tools.

Each installer is idempotent. A marker (`~/.devbox-install`) suppresses the
prompt afterwards.

## Docker inside the guest

The image runs its own rootless Docker daemon (started by the in-guest
process supervisor, owned by the user). In every login shell, `DOCKER_HOST`
is set to the in-guest socket (`unix:///run/user/1000/docker.sock`).

All Docker state (images, containers, volumes, build cache) lives in the
profile's `devbox-<profile>-docker` volume at `/data/docker`.
