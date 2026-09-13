###########################################################
# NextUI SCUMMVMSA Pak — standalone ScummVM
###########################################################

# ScummVM source — pinned tag/commit for reproducibility
SCUMMVM_REPO := https://github.com/scummvm/scummvm.git
SCUMMVM_HASH := fed42f2068dcafc6aafa1c28c77e4c88def74b66
SCUMMVM_VER  := 2026.3.0

# minui-power-control — power button sleep/shutdown for standalone emulators.
# Release asset is a makeself self-extracting binary; pinned by sha256.
MPC_VERSION := 3.0.0
MPC_URL     := https://github.com/ben16w/minui-power-control/releases/download/$(MPC_VERSION)/minui-power-control
MPC_SHA256  := 9ea701b145b876a8f65b4152f1d6bf273069d16ad5aa8d91e615639f43e10c6e
MPC_BIN     := .cache/minui-power-control-$(MPC_VERSION)

# Pak metadata
PAK_NAME         := SCUMMVMSA
RELEASE_FILENAME := $(PAK_NAME).pak.zip

# Directories
BUILD_DIR := build
DIST_DIR  := $(BUILD_DIR)/release
STAGE_DIR := $(BUILD_DIR)/stage
PAK_DIR   := $(BUILD_DIR)/$(PAK_NAME).pak
CACHE_DIR := .cache/scummvm
SENTINEL  := .cache/.scummvm-$(SCUMMVM_HASH)

# One pinned image: gcc 8.3, glibc 2.28 sysroot (older than every supported
# firmware), cortex-a53 output runs on both A53 and A55 devices.
TOOLCHAIN     := ghcr.io/loveretro/tg5040-toolchain@sha256:f131c6af64029a8723d0ce8d3c2682642f5f091b04714f6beedda9bec18477ab
CPU_FLAGS     := -mcpu=cortex-a53 -mtune=cortex-a53
GLIBC_CEILING := 2.28

# ScummVM configure flags (evaluated inside the container).
# No cloud/networking stack, no fluidsynth (no soundfont on device), no TTS.
# Virtual keyboard is enabled so save names can be typed with the gamepad.
CONFIGURE_FLAGS := \
	--host=aarch64-nextui-linux-gnu \
	--enable-release-mode \
	--enable-optimizations \
	--enable-vkeybd \
	--disable-cloud \
	--disable-sdlnet \
	--disable-libcurl \
	--disable-discord \
	--disable-fluidsynth \
	--disable-updates \
	--disable-tts

JOBS := $$(nproc)

###########################################################
# Phony targets
###########################################################

.PHONY: all checkout deps build libs verify package deploy clean distclean help

all: package

help:
	@echo "NextUI SCUMMVMSA Pak build system"
	@echo ""
	@echo "Targets:"
	@echo "  make package    Build ScummVM and create $(RELEASE_FILENAME)"
	@echo "  make build      Cross-compile ScummVM inside the pinned toolchain image"
	@echo "  make verify     Check the binary's architecture, RPATH, and glibc ceiling"
	@echo "  make deploy     Push the assembled pak to the device over adb"
	@echo "  make checkout   Clone/update ScummVM source"
	@echo "  make deps       Download minui-power-control (pinned, sha256-checked)"
	@echo "  make clean      Remove build artifacts"
	@echo "  make distclean  Remove build artifacts and cached source"

###########################################################
# Source checkout — pinned to SCUMMVM_HASH for reproducibility
###########################################################

checkout: $(SENTINEL)

$(SENTINEL):
	@echo "==> Checking out ScummVM @ $(SCUMMVM_HASH) (v$(SCUMMVM_VER))"
	@mkdir -p .cache
	@if [ ! -d "$(CACHE_DIR)/.git" ]; then \
		git clone --depth 1 $(SCUMMVM_REPO) $(CACHE_DIR); \
	fi
	@cd $(CACHE_DIR) && \
		git fetch --depth=1 origin $(SCUMMVM_HASH) && \
		git checkout $(SCUMMVM_HASH)
	@touch $(SENTINEL)

###########################################################
# Dependencies — minui-power-control release binary
###########################################################

deps: $(MPC_BIN)

$(MPC_BIN):
	@echo "==> Downloading minui-power-control $(MPC_VERSION)"
	@mkdir -p .cache
	curl -fL --retry 3 -o $(MPC_BIN) $(MPC_URL)
	@echo "$(MPC_SHA256)  $(MPC_BIN)" | shasum -a 256 -c -

###########################################################
# Build — cross-compile inside Docker
###########################################################

build: $(SENTINEL)
	@echo "==> Building ScummVM $(SCUMMVM_VER) with $(TOOLCHAIN)"
	@mkdir -p $(BUILD_DIR)
	docker run --rm \
		-v "$(CURDIR)":/workspace \
		-w /workspace/$(CACHE_DIR) \
		$(TOOLCHAIN) \
		/bin/bash /workspace/scripts/docker-build.sh "$(STAGE_DIR)"
	@test -f "$(STAGE_DIR)/usr/bin/scummvm" || \
		{ echo "Error: $(STAGE_DIR)/usr/bin/scummvm missing after build."; exit 1; }

###########################################################
# Shared library collection + verification
###########################################################

libs: build
	@echo "==> Collecting shared libraries into pak lib/"
	@mkdir -p "$(PAK_DIR)/lib"
	docker run --rm \
		-v "$(CURDIR)":/workspace \
		-w /workspace \
		$(TOOLCHAIN) \
		/bin/sh scripts/collect-libs.sh \
			"$(STAGE_DIR)/usr/bin/scummvm" "$(PAK_DIR)/lib"

verify:
	@test -f "$(STAGE_DIR)/usr/bin/scummvm" || \
		{ echo "Error: $(STAGE_DIR)/usr/bin/scummvm is missing; run make build."; exit 1; }
	@test -d "$(PAK_DIR)/lib" || \
		{ echo "Error: $(PAK_DIR)/lib is missing; run make libs."; exit 1; }
	@docker run --rm \
		-v "$(CURDIR)":/workspace \
		-w /workspace \
		$(TOOLCHAIN) \
		/bin/sh scripts/verify-binary.sh \
			"$(STAGE_DIR)/usr/bin/scummvm" "$(PAK_DIR)/lib" $(GLIBC_CEILING)

###########################################################
# Packaging — one Pak Store archive, contents at its root
###########################################################

package: deps libs
	@$(MAKE) --no-print-directory verify
	@grep -q '"release_filename": "$(RELEASE_FILENAME)"' pak.json || \
		{ echo "Error: pak.json release_filename is not $(RELEASE_FILENAME)."; exit 1; }
	@echo "==> Assembling $(PAK_NAME).pak"
	@rm -rf "$(PAK_DIR)/bin" "$(PAK_DIR)/share/scummvm"
	@mkdir -p "$(PAK_DIR)/bin" "$(PAK_DIR)/share" "$(DIST_DIR)"
	@cp launch.sh pak.json LICENSE README.md "$(PAK_DIR)/"
	@cp "$(STAGE_DIR)/usr/bin/scummvm" "$(PAK_DIR)/bin/scummvm"
	@cp "$(MPC_BIN)" "$(PAK_DIR)/bin/minui-power-control"
	@cp -R "$(STAGE_DIR)/usr/share/scummvm" "$(PAK_DIR)/share/scummvm"
	@chmod 755 "$(PAK_DIR)/launch.sh" "$(PAK_DIR)/bin/scummvm" "$(PAK_DIR)/bin/minui-power-control"
	@rm -f "$(DIST_DIR)/$(RELEASE_FILENAME)"
	@cd "$(PAK_DIR)" && zip -9 -q -r "$(CURDIR)/$(DIST_DIR)/$(RELEASE_FILENAME)" . -x '.*'
	@for f in launch.sh pak.json LICENSE bin/scummvm bin/minui-power-control; do \
		unzip -Z1 "$(DIST_DIR)/$(RELEASE_FILENAME)" | grep -qx "$$f" || \
			{ echo "Error: $$f is missing from the archive root."; exit 1; }; \
	done
	@unzip -p "$(DIST_DIR)/$(RELEASE_FILENAME)" bin/scummvm | cmp -s - "$(STAGE_DIR)/usr/bin/scummvm" || \
		{ echo "Error: archived binary differs from $(STAGE_DIR)/usr/bin/scummvm."; exit 1; }
	@echo "==> Done: $(DIST_DIR)/$(RELEASE_FILENAME)"

###########################################################
# Deploy to a connected device over adb (local testing)
###########################################################

deploy: package
	adb shell "mkdir -p /mnt/SDCARD/Emus/tg5040/$(PAK_NAME).pak"
	adb push "$(PAK_DIR)/." "/mnt/SDCARD/Emus/tg5040/$(PAK_NAME).pak/"
	@echo "==> Deployed to /mnt/SDCARD/Emus/tg5040/$(PAK_NAME).pak"

###########################################################
# Cleanup
###########################################################

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -rf .cache
