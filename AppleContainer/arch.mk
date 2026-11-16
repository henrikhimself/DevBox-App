# Apple Container specialization: platform names and CLI selection.
#
# devbox-apple builds and runs only on Apple silicon macOS with the Apple
# Container CLI. Host/backend preflight (arm64 macOS host, pinned `container`
# CLI, jq and a running backend) is performed by runtime/preflight.sh and is
# invoked by the `preflight` target and by every target that touches the
# backend. There is no fallback to another runtime or platform and no
# emulated build.

CONTAINER_CMD ?= container
RUNTIME_NAME  := apple

PLATFORM      := linux/arm64
S6_ARCH       := aarch64
SHELLCHECK_ARCH := aarch64

PREFLIGHT     := $(CURDIR)/runtime/preflight.sh

# Build and image management always use the pinned container command.
BUILD_CMD     := $(CONTAINER_CMD) build --progress plain

IMAGE_INSPECT = $(CONTAINER_CMD) image inspect $(DEVBOX_IMAGE)
IMAGE_RM      = $(CONTAINER_CMD) image rm $(DEVBOX_IMAGE)
