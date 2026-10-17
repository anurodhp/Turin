# turin: Settings (system settings) for GNUstep + Window Maker (Darwin/XNU) -- see README.md.
include $(GNUSTEP_MAKEFILES)/common.make

# the app is Settings (Settings.app, its menus, the dock); Turin is the project
APP_NAME = Settings
VERSION = 0.1
Settings_OBJC_FILES = main.m TurinUtil.m TurinIcons.m TurinPane.m TurinWindow.m TurinImage.m TurinWifi.m TurinWifiPane.m \
	TurinNetworkPane.m TurinDateTimePane.m TurinBackgroundPane.m TurinUsersPane.m
Settings_C_FILES = crypt_des.c
Settings_MAIN_MODEL_FILE =
Settings_APPLICATION_ICON = Turin.tiff
Settings_RESOURCE_FILES = icons/Turin.tiff icons/Turin.png
Settings_LOCALIZED_RESOURCE_FILES =

ADDITIONAL_OBJCFLAGS += -O2 -Wall -fblocks
# clang fuses sin(x) and cos(x) of one angle into __sincos_stret, which this system's libsystem_m does not export
ADDITIONAL_OBJCFLAGS += -fno-builtin-sin -fno-builtin-cos

include $(GNUSTEP_MAKEFILES)/application.make
