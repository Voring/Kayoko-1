//
//  main.m
//  KayokoURLHandler
//
//  一个极小的 URL 认领 App：它的唯一作用是在 LaunchServices 里为 kayoko:// 注册一个
//  真实可用的处理方（否则 Shortcuts、Safari、终端命令等外部调用会直接报
//  “无法为 URL 方案 kayoko 打开 App” / “不支持的 URL”）。
//
//  App 本身不显示任何界面：收到 URL 后立刻通过共享桥把请求转给 SpringBoard 里的
//  KayokoCore 执行，然后退出。
//

#import <UIKit/UIKit.h>

#import "../Shared/URLScheme/KayokoURLSchemeBridge.h"
#import "../Shared/URLScheme/KayokoURLSchemeProtocol.h"

static BOOL kKayokoURLHandlerReceivedURL = NO;

@interface KayokoURLHandlerDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation KayokoURLHandlerDelegate

- (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)URL
              options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    if (!KayokoURLSchemeIsKayokoURL(URL)) {
        return NO;
    }

    kKayokoURLHandlerReceivedURL = YES;
    __block BOOL handled = NO;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      handled = [[KayokoURLSchemeBridge sharedBridge] sendURL:URL source:@"url-handler-app" error:NULL];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                       exit(handled ? 0 : 1);
                     });
    });

    return YES;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    // 如果只是被误点开（没有任何 URL 进来），1.5 秒后自行退出，不留下一个空窗口。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (!kKayokoURLHandlerReceivedURL) {
                         exit(0);
                     }
                   });
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([KayokoURLHandlerDelegate class]));
    }
}
