# Shared build rules for the DevBox image specializations.
#
# Included by AppleContainer/Makefile and Docker/Makefile AFTER the
# specialization defines (see each arch.mk / Makefile):
#   DEVBOX_IMAGE   image tag
#   PLATFORM       linux/arm64 | linux/amd64
#   S6_ARCH        aarch64 | x86_64          (s6-overlay asset name)
#   BUILD_CMD      runtime build command without context/platform arguments
#   IMAGE_INSPECT  command that exits 0 when $(DEVBOX_IMAGE) exists locally
#   IMAGE_RM       command that removes $(DEVBOX_IMAGE)
#   RUNTIME_NAME   apple | docker             (hook directory selection)
# No runtime is selected here; there is no auto-detection.

COMMON_DIR     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
IMAGE_SRC      := $(COMMON_DIR)/image
BUILD_SRC      := $(COMMON_DIR)/build
HOOKS_SRC      := $(CURDIR)/runtime/image
DOWNLOADS_SH   := $(BUILD_SRC)/downloads.sh
PREPARE_SH     := $(BUILD_SRC)/prepare-context.sh

S6_OVERLAY_VERSION := 3.2.2.0

CONTEXT_DIR    := tmp/build-context
STATE_DIR      := tmp/state
BUILD_STAMP    := $(STATE_DIR)/build.stamp

.PHONY: prepare-context build clean distclean FORCE

FORCE:

# ── Downloads (native architecture only) ─────────────────────────────────────
# s6-overlay: release metadata, then the native-arch and noarch archives, each
# verified against the SHA-256 digest published in the release metadata.
tmp/s6-overlay.json: $(DOWNLOADS_SH) | tmp
	$(DOWNLOADS_SH) gh-json $@ just-containers/s6-overlay $(S6_OVERLAY_VERSION)

tmp/s6-overlay-arch.tar.xz: tmp/s6-overlay.json $(DOWNLOADS_SH) | tmp
	$(DOWNLOADS_SH) gh-release $@ tmp/s6-overlay.json s6-overlay-$(S6_ARCH).tar.xz

tmp/s6-overlay-noarch.tar.xz: tmp/s6-overlay.json $(DOWNLOADS_SH) | tmp
	$(DOWNLOADS_SH) gh-release $@ tmp/s6-overlay.json s6-overlay-noarch.tar.xz

tmp $(STATE_DIR):
	mkdir -p $@

DOWNLOADS := tmp/s6-overlay-arch.tar.xz tmp/s6-overlay-noarch.tar.xz

# ── Rebuild gate ─────────────────────────────────────────────────────────────
# build-config changes whenever the tag, platform, versions or architecture
# names change (rewritten only on change, so its mtime is a valid trigger).
$(STATE_DIR)/build-config: FORCE | $(STATE_DIR)
	@printf 'image=%s\nplatform=%s\ns6=%s\ns6arch=%s\nruntime=%s\n' \
	  '$(DEVBOX_IMAGE)' '$(PLATFORM)' '$(S6_OVERLAY_VERSION)' '$(S6_ARCH)' '$(RUNTIME_NAME)' > $@.new
	@if cmp -s $@.new $@; then rm -f $@.new; else mv $@.new $@; fi

# inputs.fingerprint covers the content and relative path of every allowlisted
# source file, so additions, removals, renames and edits all change it. Mode
# changes (including runtime hooks) do not.
$(STATE_DIR)/inputs.fingerprint: FORCE | $(STATE_DIR)
	@$(PREPARE_SH) --fingerprint --runtime-dir '$(CURDIR)' > $@.new
	@if cmp -s $@.new $@; then rm -f $@.new; else mv $@.new $@; fi

# ── Context preparation and build ────────────────────────────────────────────
prepare-context: $(DOWNLOADS)
	$(PREPARE_SH) --runtime-dir '$(CURDIR)' --downloads tmp --out $(CONTEXT_DIR)

# The stamp is the build gate. It is invalidated by input/config/download
# changes (prerequisites) and by the local image having been removed: when the
# image is missing, image-present is rewritten so that it is newer than the
# stamp, which forces the build below. When the image exists the file is left
# untouched (or created with the stamp's own mtime), so it never causes a
# spurious rebuild.
$(STATE_DIR)/image-present: FORCE | $(STATE_DIR)
	@if $(IMAGE_INSPECT) >/dev/null 2>&1; then \
	  if [ ! -f $@ ]; then \
	    if [ -f $(BUILD_STAMP) ]; then : > $@; touch -r $(BUILD_STAMP) $@; else : > $@; fi; \
	  fi; \
	else \
	  : > $@; \
	fi

build: $(BUILD_STAMP)

$(BUILD_STAMP): $(STATE_DIR)/inputs.fingerprint $(STATE_DIR)/build-config \
	$(STATE_DIR)/image-present $(DOWNLOADS)
	$(PREPARE_SH) --runtime-dir '$(CURDIR)' --downloads tmp --out $(CONTEXT_DIR)
	cd $(CONTEXT_DIR) && $(BUILD_CMD) --platform $(PLATFORM) -f Containerfile -t $(DEVBOX_IMAGE) .
	: > $(STATE_DIR)/image-present
	touch $@

# ── Clean ────────────────────────────────────────────────────────────────────
clean:
	- rm -rf tmp

distclean: clean
	- $(IMAGE_RM)
