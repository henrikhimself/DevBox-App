# Docker specialization: platform names and CLI selection.
#
# devbox-docker targets native Linux amd64 only. Host/engine preflight
# (Linux, amd64, local Unix socket, rootful, no userns-remap) is performed by
# runtime/preflight.sh and is invoked by the `preflight` target and by every
# target that touches the daemon. There is no fallback to another runtime or
# platform and no emulated build.

DOCKER_CMD    ?= docker
RUNTIME_NAME  := docker

PLATFORM      := linux/amd64
S6_ARCH       := x86_64

PREFLIGHT     := $(CURDIR)/runtime/preflight.sh

# Build and image management always use the pinned docker command.
BUILD_CMD     := $(DOCKER_CMD) build --progress plain
IMAGE_INSPECT = $(DOCKER_CMD) image inspect $(DEVBOX_IMAGE)
IMAGE_RM      = $(DOCKER_CMD) image rm $(DEVBOX_IMAGE)
