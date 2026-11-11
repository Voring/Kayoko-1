include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := KayokoURLHandler

KayokoURLHandler_FILES += main.m
KayokoURLHandler_FILES += ../Shared/URLScheme/KayokoURLSchemeBridge.m
KayokoURLHandler_FILES += ../Shared/URLScheme/KayokoURLSchemeProtocol.m

KayokoURLHandler_CFLAGS += -fobjc-arc
KayokoURLHandler_CFLAGS += -I../Shared/URLScheme
# 这个 App 独立运行在 jbroot/Applications 里，不能依赖 libroothide（注入环境的
# 加载路径在 App 内解析不到）。改用自身 bundle 位置推算 jbroot 根。
KayokoURLHandler_CFLAGS += -DKAYOKO_STANDALONE_URL_HANDLER=1

KayokoURLHandler_FRAMEWORKS += UIKit

include $(THEOS_MAKE_PATH)/application.mk
