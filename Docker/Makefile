# Build tooling for the DevBox image on Docker Engine (native Linux amd64).
# Shared download/context/rebuild rules live in ../Common/build/common.mk.

# Current image tag is centralized in Common/image/tag.txt; the build
# always uses it (forced via the `override` keyword, so an env or
# DEVBOX_IMAGE is ignored). Lifecycle scripts read the same tag.txt,
# but an env DEVBOX_DEFAULT_IMAGE still overrides them for running only.
TAG_FILE := $(CURDIR)/../Common/image/tag.txt
TAG := $(shell cat "$(TAG_FILE)")
override DEVBOX_IMAGE := localhost:5000/hj/devbox-docker:$(TAG)

include ./arch.mk
include ../Common/build/common.mk

.DEFAULT_GOAL := help

.DELETE_ON_ERROR:
.SUFFIXES:

.PHONY: help preflight run test check-test-prereqs

help:
	@printf 'Targets:\n'
	@printf '  preflight        Check host, Docker endpoint and Engine mode (no changes)\n'
	@printf '  prepare-context  Assemble the build context in tmp/build-context (downloads and verifies s6-overlay and Node first)\n'
	@printf '  build      Preflight, prepare the context and build $(DEVBOX_IMAGE)\n'
	@printf '  run        Build, then run an interactive throwaway container (SSH on host port 2222)\n'
	@printf '  test       Preflight the Docker host, then run the full feature test suite (needs no devbox-* containers)\n'
	@printf '  clean      Remove tmp/ (downloads, build context and build state)\n'
	@printf '  distclean  clean, then remove the built image\n'

preflight:
	@$(PREFLIGHT) build

# ── Run ──────────────────────────────────────────────────────────────────────

# Same flag source as the profile lifecycle (runtime/adapter.sh); no Apple
# --no-dns, tmpfs or swap options.
run: build
	@$(CURDIR)/runtime/throwaway.sh $(DEVBOX_IMAGE)

# ── Test ─────────────────────────────────────────────────────────────────────

# Host/engine preflight including /dev/fuse and /dev/net/tun, plus jq. Never
# starts, switches or reconfigures a daemon.
check-test-prereqs:
	@$(PREFLIGHT) launch
	@command -v jq >/dev/null 2>&1 \
	  || { printf 'prerequisite failed: jq not found in PATH.\n' >&2; exit 1; }

# The suite runs against the real daemon and needs a host with no devbox-*
# containers in any state; tests/run-tests.sh refuses to run otherwise and
# never removes anything it did not create.
test: check-test-prereqs
	@test -f ./tests/run-tests.sh \
	  || { printf 'prerequisite failed: tests/run-tests.sh is not present.\n' >&2; exit 1; }
	@echo "==> Running feature test suite"
	@bash ./tests/run-tests.sh

# Image-building targets validate the host and daemon first. The preflight is
# an order-only prerequisite of the state/download directories that every
# file target depends on, so a rejected configuration performs no download,
# creates no tmp/ state and builds nothing. Being order-only it never by itself
# invalidates a build.
tmp $(STATE_DIR): | preflight
prepare-context $(BUILD_STAMP): | preflight
