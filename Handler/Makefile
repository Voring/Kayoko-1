include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := KayokoURLHandler

KayokoURLHandler_FILES += main.m
KayokoURLHandler_FILES += ../Shared/URLScheme/KayokoURLSchemeBridge.m
KayokoURLHandler_FILES += ../Shared/URLScheme/KayokoURLSchemeProtocol.m

KayokoURLHandler_CFLAGS += -fobjc-arc
KayokoURLHandler_CFLAGS += -I../Shared/URLScheme

KayokoURLHandler_FRAMEWORKS += UIKit
KayokoURLHandler_LIBRARIES += substrate
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
KayokoURLHandler_LIBRARIES += roothide
endif

include $(THEOS_MAKE_PATH)/application.mk
