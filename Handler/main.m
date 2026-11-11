//
//  main.m
//  KayokoURLHandler
//
//  极小的 URL 认领 App。正常情况下它根本不会被启动——SpringBoard 侧的
//  KayokoAppLaunchHooks 会在“打开 App”这一步就把 kayoko:// 拦下来直接执行，
//  所以用户看不到任何界面。
//
//  这里保留两个兜底能力：
//  1. 万一仍然被拉起，收到 URL 后立即经共享桥转发给 KayokoCore，然后极快退出，
//     把可见的空白画面压到最短；
//  2. kayoko://diag 在被拉起时把 SpringBoard 侧记录的诊断信息写进系统剪贴板，
//     方便用户直接粘贴回传。
//

#import <UIKit/UIKit.h>

#import "../Shared/URLScheme/KayokoURLSchemeBridge.h"
#import "../Shared/URLScheme/KayokoURLSchemeProtocol.h"

static BOOL kKayokoURLHandlerReceivedURL = NO;

@interface KayokoURLHandlerDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation KayokoURLHandlerDelegate

- (void)copyDiagnosticsToPasteboard {
    NSString *path = [KayokoURLSchemeRequestDirectoryPath() stringByAppendingPathComponent:@"diag.txt"];
    NSString *body = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if ([body length] == 0) {
        body = @"(diag.txt 不存在或为空：说明 SpringBoard 侧插件没有写出诊断信息)";
    }
    NSString *text = [NSString stringWithFormat:@"=== Kayoko URL diag ===\n%@app launched at %@\n",
                                                body, [NSDate date]];
    [UIPasteboard generalPasteboard].string = text;
}

- (BOOL)isDiagnosticURL:(NSURL *)URL {
    NSString *host = [[URL host] lowercaseString];
    NSString *path = [[URL path] lowercaseString];
    NSString *absolute = [[URL absoluteString] lowercaseString];
    return [host isEqualToString:@"diag"] || [path isEqualToString:@"/diag"] ||
           [absolute hasSuffix:@"//diag"];
}

- (BOOL)handleURL:(NSURL *)URL {
    if (!KayokoURLSchemeIsKayokoURL(URL)) {
        return NO;
    }

    kKayokoURLHandlerReceivedURL = YES;

    if ([self isDiagnosticURL:URL]) {
        [self copyDiagnosticsToPasteboard];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         exit(0);
                       });
        return YES;
    }

    __block BOOL handled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      handled = [[KayokoURLSchemeBridge sharedBridge] sendURL:URL source:@"url-handler-app" error:NULL];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                     dispatch_get_main_queue(), ^{
                       exit(handled ? 0 : 1);
                     });
    });

    return YES;
}

- (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)URL
              options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    return [self handleURL:URL];
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (launchURL && [self handleURL:launchURL]) {
        return YES;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
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
