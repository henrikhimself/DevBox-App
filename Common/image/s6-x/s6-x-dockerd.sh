#!/usr/bin/env bash
# Common rootless dockerd service. Guest device preparation is runtime
# specific and is delegated to /s6-x/x-runtime-devices.sh (installed by the
# runtime hook): Apple creates /dev/net/tun and /dev/fuse in its VM, Docker
# validates the devices passed through by `docker run --device`.
# An unsuccessful hook aborts the service start.
/s6-x/s6-add-run.sh dockerd 'longrun' \
'install -d -m 755 -o bob -g bob /data/docker
install -d -m 700 -o bob -g bob /run/user/1000

/s6-x/x-runtime-devices.sh || exit 1

exec s6-setuidgid bob \
env HOME=/opt/docker XDG_RUNTIME_DIR=/run/user/1000 DOCKERD_ROOTLESS_ROOTLESSKIT_NET=pasta \
dockerd-rootless.sh --config-file /opt/docker/daemon.json'

/s6-x/s6-add-log.sh dockerd

/s6-x/s6-add-readiness.sh dockerd \
'exec s6-setuidgid bob \
env HOME=/opt/docker XDG_RUNTIME_DIR=/run/user/1000 DOCKER_HOST=unix:///run/user/1000/docker.sock \
docker info >/dev/null 2>&1'
