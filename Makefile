export TARGET = iphone:clang:16.0:16.0
export THEOS = $(HOME)/theos
export ARCHS = arm64
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = keychain_cleanerd
keychain_cleanerd_FILES = daemon/keychain_cleanerd.c
keychain_cleanerd_CFLAGS = -w
keychain_cleanerd_LDFLAGS = -lsqlite3
keychain_cleanerd_INSTALL_PATH = /usr/libexec

BUNDLE_NAME = KeychainCleaner
KeychainCleaner_FILES = KCRootListController.m
KeychainCleaner_FRAMEWORKS = UIKit
KeychainCleaner_INSTALL_PATH = /Library/PreferenceBundles
KeychainCleaner_CFLAGS = -fobjc-arc
KeychainCleaner_LDFLAGS = -Wl,-flat_namespace,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/KeychainCleaner.plist"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/LaunchDaemons"$(ECHO_END)
	$(ECHO_NOTHING)cp daemon/com.hermes.keychaincleaner.plist "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/"$(ECHO_END)
