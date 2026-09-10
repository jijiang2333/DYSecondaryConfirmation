TARGET = iphone:clang:16.5:14.0
ARCHS = arm64 arm64e

SCHEME ?= rootless
ifeq ($(SCHEME),roothide)
export THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(SCHEME),rootful)
unexport THEOS_PACKAGE_SCHEME
else ifeq ($(SCHEME),rootless)
export THEOS_PACKAGE_SCHEME = rootless
else
$(error Unknown SCHEME=$(SCHEME); use rootless, rootful, or roothide)
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYLike

DYLike_FILES = Sources/Hooks/DYLikeHooks.m \
	Sources/Core/DYLikeCore.m \
	Sources/UI/DYLikePrompt.m \
	Sources/Settings/DYLikeSettings.m

DYLike_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
	-ISources/Core \
	-ISources/UI \
	-ISources/Settings
DYLike_FRAMEWORKS = UIKit Foundation QuartzCore
DYLike_LDFLAGS = -lobjc

include $(THEOS_MAKE_PATH)/tweak.mk
