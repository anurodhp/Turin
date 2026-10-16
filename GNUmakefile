# turin: System Preferences for GNUstep + Window Maker (Darwin/XNU) -- see README.md.
include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = Turin
VERSION = 0.1
Turin_OBJC_FILES = main.m TurinUtil.m TurinIcons.m TurinPane.m TurinWindow.m TurinImage.m TurinWifi.m TurinWifiPane.m \
	TurinNetworkPane.m TurinDateTimePane.m TurinBackgroundPane.m TurinUsersPane.m
Turin_C_FILES = crypt_des.c
Turin_MAIN_MODEL_FILE =
Turin_APPLICATION_ICON = Turin.tiff
Turin_RESOURCE_FILES = icons/Turin.tiff icons/Turin.png
Turin_LOCALIZED_RESOURCE_FILES =

ADDITIONAL_OBJCFLAGS += -O2 -Wall -fblocks
# clang fuses sin(x) and cos(x) of one angle into __sincos_stret, which this system's libsystem_m does not export
ADDITIONAL_OBJCFLAGS += -fno-builtin-sin -fno-builtin-cos

include $(GNUSTEP_MAKEFILES)/application.make
