include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := KayokoURLHandler

KayokoURLHandler_FILES += main.m
KayokoURLHandler_FILES += ../Shared/URLScheme/KayokoURLSchemeBridge.m
KayokoURLHandler_FILES += ../Shared/URLScheme/KayokoURLSchemeProtocol.m

KayokoURLHandler_CFLAGS += -fobjc-arc
KayokoURLHandler_CFLAGS += -I../Shared/URLScheme

KayokoURLHandler_FRAMEWORKS += UIKit

# 这个 App 装在 jbroot 的 /Applications 里，而 theos 给 roothide 目标写入的
# libreothide 安装名是 @loader_path/.jbroot/usr/lib/…，从 App 内部解析不到。
# 改成相对 App 位置的正确路径：App → Applications → jbroot 根 → usr/lib。
KayokoURLHandler_LDFLAGS += -Wl,-change,@loader_path/.jbroot/usr/lib/libroothide.dylib,@loader_path/../../usr/lib/libroothide.dylib

include $(THEOS_MAKE_PATH)/application.mk
