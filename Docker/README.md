# DevBox-Docker

A development environment that runs as a Docker container.

## Prerequisites

- Linux (amd64)
- [Docker](https://www.docker.com/)
- local Docker unix socket
- SSH client
- Bash
- jq
- curl
- tar
- sha256sum

## Runtime privileges

Profile launches and `make run` use:

- `--privileged`
- `--cap-add ALL`

The in-guest rootless Docker daemon does not start under Docker's default
confinement, so `--privileged` is required.

## Building the image

From this directory:

```sh
make build
```

The build creates a build context in `tmp/`. The image tag is read from `../Common/image/tag.txt`:

```
localhost:5000/hj/devbox-docker
```
