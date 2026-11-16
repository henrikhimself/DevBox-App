# Build tooling for the DevBox image on Apple Container.
# Shared download/context/rebuild rules live in ../Common/build/common.mk.

# Current image tag is centralized in Common/image/tag.txt; the build
# always uses it (forced via the `override` keyword, so an env or
# DEVBOX_IMAGE is ignored). Lifecycle scripts read the same tag.txt,
# but an env DEVBOX_DEFAULT_IMAGE still overrides them for running only.
TAG_FILE := $(CURDIR)/../Common/image/tag.txt
TAG := $(shell cat "$(TAG_FILE)")
override DEVBOX_IMAGE := localhost:5000/hj/devbox-apple:$(TAG)
RUNTIME_NAME		:= apple

include ./arch.mk
include ../Common/build/common.mk

.DEFAULT_GOAL := help

.DELETE_ON_ERROR:
.SUFFIXES:

.PHONY: help preflight run test check-test-prereqs

help:
	@printf 'Targets:\n'
	@printf '  preflight        Check host and Apple Container backend (no changes)\n'
	@printf '  prepare-context  Assemble the build context in tmp/build-context (downloads and verifies s6-overlay and Node first)\n'
	@printf '  build      Prepare the context and build $(DEVBOX_IMAGE)\n'
	@printf '  run        Build, then run an interactive throwaway container (SSH on host port 2222)\n'
	@printf '  test       Preflight the Apple Container backend, then run the full feature test suite\n'
	@printf '  clean      Remove tmp/ (downloads, build context and build state)\n'
	@printf '  distclean  clean, then remove the built image\n'

# ── Run ──────────────────────────────────────────────────────────────────────

# Preflight: validate the host and backend before anything is built.
preflight:
	@$(PREFLIGHT) build

run: build
	@$(CURDIR)/runtime/throwaway.sh $(DEVBOX_IMAGE)

# ── Test ─────────────────────────────────────────────────────────────────────

# Host/backend preflight (arm64 macOS host, pinned `container` CLI, jq and a
# running backend). Starts, switches or reconfigures nothing.
check-test-prereqs:
	@$(PREFLIGHT) launch

# The target test runner. Target Mac only: the check-test-prereqs preflight
# fails with a clear prerequisite error instead of silently selecting another
# runtime. tests/run-tests.sh additionally requires no devbox-* containers
# on the host.
test: check-test-prereqs
	@echo "==> Running feature test suite"
	@bash ./tests/run-tests.sh

# Image-building targets validate the host and backend first. The preflight is
# an order-only prerequisite of the state/download directories that every file
# target depends on, so a rejected configuration performs no download, creates
# no tmp/ state and builds nothing. Being order-only it never by itself
# invalidates a build.
tmp $(STATE_DIR): | preflight
prepare-context $(BUILD_STAMP): | preflight
