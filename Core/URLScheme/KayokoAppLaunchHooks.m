//
//  KayokoAppLaunchHooks.m
//  Kayoko
//
//  外部（快捷指令 / 其他 App / 终端）打开 kayoko:// 时，LaunchServices 会先把请求
//  交给 SpringBoard 的 FBSystemService 去“启动”认领该 scheme 的 KayokoURLHandler.app，
//  于是屏幕上会闪一下空白 App。这里在“启动 App”这一步之前就把请求接住：
//  就地交给 KayokoCore 的 URL scheme 处理器执行（正常弹出主面板），并且不再放行
//  原始启动请求——App 因此完全不会被拉起，也就没有任何界面出现。
//
//  该文件只对 SpringBoard 生效：其它被注入的进程里根本不存在 FBSystemService，
//  安装时会整段跳过。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(FBSystemService);

@interface FBSystemService : NSObject
// SpringBoard 处理“打开某 App”的统一入口，URL 藏在 options.url 里。
- (void)activateApplication:(id)application
                  requestID:(unsigned int)requestID
                    options:(id)options
                     source:(id)source
             originalSource:(id)originalSource
                 withResult:(id)result;
@end

CHOptimizedMethod6(self, void, FBSystemService, activateApplication, id, application, requestID, unsigned int,
                   requestID, options, id, options, source, id, source, originalSource, id, originalSource, withResult,
                   id, result) {
    NSURL *URL = nil;
    @try {
        if ([options respondsToSelector:@selector(url)]) {
            URL = [options url];
        }
    } @catch (__unused NSException *exception) {
        URL = nil;
    }

    if (KayokoURLSchemeIsKayokoURL(URL)) {
        KayokoURLSchemeInterceptOpenURL(URL, nil);
        if (result) {
            // 直接告诉调用方“已经处理好了”，不启动 App。
            ((void (^)(id, id))result)(nil, nil);
        }
        return;
    }

    CHSuper6(FBSystemService, activateApplication, application, requestID, requestID, options, options, source, source,
             originalSource, originalSource, withResult, result);
}

static void KayokoInstallAppLaunchHooks(void) {
    Class systemServiceClass = NSClassFromString(@"FBSystemService");
    if (!systemServiceClass) {
        return;
    }

    CHLoadClass_(&FBSystemService$, systemServiceClass);

    // 不用严格的类型编码比对：iOS 16 上 requestID 的实际类型在 I / Q 之间变化过，
    // 严格比对会导致钩子被静默跳过。参数全走 8 字节槽位，类型宽窄不影响 ABI，
    // 所以只校验“确实是 6 参方法”即可。
    SEL activateSelector = @selector(activateApplication:requestID:options:source:originalSource:withResult:);
    Method activateMethod = class_getInstanceMethod(systemServiceClass, activateSelector);
    if (activateMethod && method_getNumberOfArguments(activateMethod) == 8) {
        CHHook6(FBSystemService, activateApplication, requestID, options, source, originalSource, withResult);
    }
}

__attribute__((constructor)) static void KayokoAppLaunchHooksEntry(void) {
    @autoreleasepool {
        if (NSClassFromString(@"FBSystemService") == nil) {
            return;
        }
        // FrontBoard / SpringBoard 的类在插件加载时可能还没全部 realize，
        // 先立即尝试一次，再在主队列上补一次。
        KayokoInstallAppLaunchHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         KayokoInstallAppLaunchHooks();
                       });
    }
}
