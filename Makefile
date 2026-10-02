TARGET := iphone:clang:6.1:6.0
ARCHS := armv7
include $(THEOS)/makefiles/common.mk
include mbedtls-sources.mk

APPLICATION_NAME := LocalSend6
LocalSend6_FILES := main.m AppDelegate.m LSLocalization.m LSDesign.m LSFilesystemPicker.m LSReceiver.m LSPhotoImporter.m LSHEICDecoder.c LSClock.c LSTransport.m LSConnection.m LSIdentity.m $(MBEDTLS_SOURCES)
LocalSend6_FRAMEWORKS := UIKit Foundation Security QuartzCore CoreGraphics ImageIO AssetsLibrary AVFoundation
LocalSend6_CFLAGS := -fobjc-arc -O2 -DMBEDTLS_PLATFORM_MS_TIME_ALT -Ivendor/heic-ios/include -Ivendor/mbedtls-3.6.7/include -Ivendor/mbedtls-3.6.7/library -Ivendor/mbedtls-3.6.7/3rdparty/everest/include -Ivendor/mbedtls-3.6.7/3rdparty/p256-m -Ivendor/mbedtls-3.6.7/3rdparty/p256-m/p256-m
LocalSend6_LDFLAGS := -Lvendor/heic-ios/lib -lheif -lde265 -lc++
LocalSend6_RESOURCE_DIRS := Resources
LocalSend6_CODESIGN_FLAGS := -S
include $(THEOS_MAKE_PATH)/application.mk
