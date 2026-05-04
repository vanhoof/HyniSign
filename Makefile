# HyniSign Makefile
#
# Builds a sideload-ready dylib at build/HyniSign.dylib. Drag this into
# Sideloadly's "Inject dylibs" list when re-signing the Minecraft IPA.
#
# Targets:
#   make            Build sideload-ready dylib at build/HyniSign.dylib
#   make clean      Remove build artifacts
#
# Build flags:
#   HYNISIGN_VERBOSE=1   Log every keychain call (chatty; default logs only the
#                     stripping events, which are rare and informative)
#
# Requires Theos: https://theos.dev/  (set $THEOS in your shell rc)

TARGET := iphone:clang:latest:14.0
ARCHS  := arm64

ifeq ($(HYNISIGN_VERBOSE),1)
EXTRA_CFLAGS += -DHYNISIGN_VERBOSE=1
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME              = HyniSign
HyniSign_FILES      = Tweak.x fishhook.c access_group.c
HyniSign_FRAMEWORKS = Foundation Security
HyniSign_CFLAGS     = -fobjc-arc -Wno-deprecated-declarations $(EXTRA_CFLAGS)

include $(THEOS_MAKE_PATH)/tweak.mk

# Post-build: produce a sideload-ready copy with @executable_path install name
# and an ad-hoc signature. Sideloadly will re-sign with the user's cert when
# injecting into the IPA.
all::
	@mkdir -p build
	@cp .theos/obj/debug/HyniSign.dylib build/HyniSign.dylib
	@install_name_tool -id "@executable_path/HyniSign.dylib" build/HyniSign.dylib 2>/dev/null
	@codesign --remove-signature build/HyniSign.dylib 2>/dev/null || true
	@codesign -s - build/HyniSign.dylib 2>/dev/null
	@echo "==> Sideload-ready dylib: build/HyniSign.dylib"

clean::
	@rm -rf build
