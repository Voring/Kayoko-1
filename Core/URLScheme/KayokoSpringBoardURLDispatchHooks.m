//
//  KayokoSpringBoardURLDispatchHooks.m
//  Kayoko
//
//  参考 ShellX（ScreenshotShell）的做法：它没有独立 App、也没有 CFBundleURLTypes，
//  而是直接钩 SpringBoard 自己的 URL 分发方法族：
//      -application:handleOpenURL:
//      -application:openURL:options:
//      -application:openURL:sourceApplication:annotation:
//      -applicationOpenURL:
//      -applicationOpenURL:publicURLsOnly:
//      -applicationOpenURL:withApplication:sender:publicURLsOnly:animating:needsConfirm:options:windowContext:
//  任何来源（快捷指令、别的插件）发过来的 URL 最后都要在这里过一遍，
//  命中 kayoko / Prefs:root=Kayoko_* 就地弹面板，不拉起任何 App。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(SpringBoard);

@interface SpringBoard : NSObject
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url;
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(id)options;
- (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)url
    sourceApplication:(id)source
           annotation:(id)annotation;
- (BOOL)applicationOpenURL:(NSURL *)url;
- (BOOL)applicationOpenURL:(NSURL *)url publicURLsOnly:(BOOL)only;
- (BOOL)applicationOpenURL:(NSURL *)url
            withApplication:(id)application
                   sender:(id)sender
            publicURLsOnly:(BOOL)only
                animating:(BOOL)animating
              needsConfirm:(BOOL)confirm
                  options:(id)options
             windowContext:(id)context;
@end

static NSString *KayokoDispatchDiagPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      path = [KayokoURLSchemeRequestDirectoryPath() stringByAppendingPathComponent:@"diag.txt"];
    });
    return path;
}

static void KayokoDispatchDiag(NSString *line) {
    @autoreleasepool {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *entry = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
        NSString *path = KayokoDispatchDiagPath();
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
            handle = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        @try {
            [handle seekToEndOfFile];
            [handle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        } @catch (__unused NSException *exception) {
        }
    }
}

static BOOL KayokoDispatchIsOurs(NSURL *URL) {
    if (![URL isKindOfClass:[NSURL class]]) {
        return NO;
    }
    if (KayokoURLSchemeIsKayokoURL(URL)) {
        return YES;
    }
    NSString *scheme = [[URL scheme] lowercaseString];
    if (!([scheme isEqualToString:@"prefs"] || [scheme isEqualToString:@"app-prefs"])) {
        return NO;
    }
    NSString *all = [[[URL absoluteString] lowercaseString] stringByRemovingPercentEncoding] ?: @"";
    return [all rangeOfString:@"root=kayoko"].location != NSNotFound;
}

static void KayokoDispatchDeliver(NSURL *URL, NSString *source) {
    KayokoDispatchDiag([NSString stringWithFormat:@"hit %@ url=%@", source, [URL absoluteString]]);
    NSString *all = [[[URL absoluteString] lowercaseString] stringByRemovingPercentEncoding] ?: @"";
    if ([all rangeOfString:@"diag"].location != NSNotFound) {
        NSString *body = [NSString stringWithContentsOfFile:KayokoDispatchDiagPath()
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
        [UIPasteboard generalPasteboard].string =
            [NSString stringWithFormat:@"=== Kayoko URL diag (springboard) ===\n%@handled by SpringBoard at %@ (App 未被启动)\n",
                                       body ?: @"(diag.txt 为空)\n", [NSDate date]];
        return;
    }
    KayokoURLSchemeInterceptOpenURL([NSURL URLWithString:[NSString stringWithFormat:@"%@://show", kKayokoURLScheme]], nil);
}

CHOptimizedMethod2(self, BOOL, SpringBoard, application, UIApplication *, application, handleOpenURL, NSURL *, url) {
    if (KayokoDispatchIsOurs(url)) {
        KayokoDispatchDeliver(url, @"SpringBoard handleOpenURL");
        return YES;
    }
    return CHSuper2(SpringBoard, application, application, handleOpenURL, url);
}

CHOptimizedMethod3(self, BOOL, SpringBoard, application, UIApplication *, application, openURL, NSURL *, url, options, id, options) {
    if (KayokoDispatchIsOurs(url)) {
        KayokoDispatchDeliver(url, @"SpringBoard openURL:options:");
        return YES;
    }
    return CHSuper3(SpringBoard, application, application, openURL, url, options, options);
}

CHOptimizedMethod4(self, BOOL, SpringBoard, application, UIApplication *, application, openURL, NSURL *, url, sourceApplication,
                   id, source, annotation, id, annotation) {
    if (KayokoDispatchIsOurs(url)) {
        KayokoDispatchDeliver(url, @"SpringBoard openURL:sourceApplication:");
        return YES;
    }
    return CHSuper4(SpringBoard, application, application, openURL, url, sourceApplication, source, annotation, annotation);
}

CHOptimizedMethod1(self, BOOL, SpringBoard, applicationOpenURL, NSURL *, url) {
    if (KayokoDispatchIsOurs(url)) {
        KayokoDispatchDeliver(url, @"SpringBoard applicationOpenURL");
        return YES;
    }
    return CHSuper1(SpringBoard, applicationOpenURL, url);
}

CHOptimizedMethod2(self, BOOL, SpringBoard, applicationOpenURL, NSURL *, url, publicURLsOnly, BOOL, only) {
    if (KayokoDispatchIsOurs(url)) {
        KayokoDispatchDeliver(url, @"SpringBoard applicationOpenURL:publicURLsOnly:");
        return YES;
    }
    return CHSuper2(SpringBoard, applicationOpenURL, url, publicURLsOnly, only);
}

CHOptimizedMethod8(self, BOOL, SpringBoard, applicationOpenURL, NSURL *, url, withApplication, id, application, sender, id, sender,
                   publicURLsOnly, BOOL, only, animating, BOOL, animating, needsConfirm, BOOL, confirm, options, id, options,
                   windowContext, id, context) {
    if (KayokoDispatchIsOurs(url)) {
        KayokoDispatchDeliver(url, @"SpringBoard applicationOpenURL:withApplication:");
        return YES;
    }
    return CHSuper8(SpringBoard, applicationOpenURL, url, withApplication, application, sender, sender, publicURLsOnly, only,
                    animating, animating, needsConfirm, confirm, options, options, windowContext, context);
}

__attribute__((constructor)) static void KayokoSpringBoardURLDispatchHooksEntry(void) {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          Class boardClass = NSClassFromString(@"SpringBoard");
          if (!boardClass) {
              KayokoDispatchDiag(@"install: SpringBoard 类不存在");
              return;
          }
          CHLoadClass_(&SpringBoard$, boardClass);

          if ([boardClass instancesRespondToSelector:@selector(application:handleOpenURL:)]) {
              CHHook2(SpringBoard, application, handleOpenURL);
              KayokoDispatchDiag(@"install: SpringBoard handleOpenURL hooked");
          }
          if ([boardClass instancesRespondToSelector:@selector(application:openURL:options:)]) {
              CHHook3(SpringBoard, application, openURL, options);
              KayokoDispatchDiag(@"install: SpringBoard openURL:options: hooked");
          }
          if ([boardClass instancesRespondToSelector:@selector(application:openURL:sourceApplication:annotation:)]) {
              CHHook4(SpringBoard, application, openURL, sourceApplication, annotation);
              KayokoDispatchDiag(@"install: SpringBoard openURL:sourceApplication: hooked");
          }
          if ([boardClass instancesRespondToSelector:@selector(applicationOpenURL:)]) {
              CHHook1(SpringBoard, applicationOpenURL);
              KayokoDispatchDiag(@"install: SpringBoard applicationOpenURL hooked");
          }
          if ([boardClass instancesRespondToSelector:@selector(applicationOpenURL:publicURLsOnly:)]) {
              CHHook2(SpringBoard, applicationOpenURL, publicURLsOnly);
              KayokoDispatchDiag(@"install: SpringBoard applicationOpenURL:publicURLsOnly: hooked");
          }
          if ([boardClass instancesRespondToSelector:@selector(applicationOpenURL:withApplication:sender:publicURLsOnly:animating:needsConfirm:options:windowContext:)]) {
              CHHook8(SpringBoard, applicationOpenURL, withApplication, sender, publicURLsOnly, animating, needsConfirm, options, windowContext);
              KayokoDispatchDiag(@"install: SpringBoard applicationOpenURL:withApplication hooked");
          }
        });
    }
}
