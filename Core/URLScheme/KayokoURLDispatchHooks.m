//
//  KayokoURLDispatchHooks.m
//  Kayoko
//
//  kayoko:// 与 Prefs:root=Kayoko_* 两个入口的唯一实现：
//  1) SpringBoard 的 URL 分发方法族（ShellX / ScreenshotShell 同款位置）——
//     覆盖快捷指令、分屏插件 ARC 菜单等所有从系统进来的 URL；
//  2) FBSystemService -openApplication:...（快捷指令直接带 URL 启动设置 App 的那条）。
//  命中即弹面板，不启动任何 App。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(SpringBoard);
CHDeclareClass(FBSystemService);

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

@interface FBSystemService : NSObject
- (void)openApplication:(id)application
            withOptions:(id)options
             originator:(id)originator
              requestID:(unsigned int)requestID
             completion:(id)completion;
@end

#pragma mark - 识别与分发

static BOOL KayokoIsTriggerURL(NSURL *URL) {
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
    NSString *all = [URL absoluteString];
    return [all rangeOfString:@"root=Kayoko"].location != NSNotFound ||
           [all rangeOfString:@"root=kayoko"].location != NSNotFound;
}

static void KayokoShowPanel(NSURL *URL) {
    KayokoURLSchemeInterceptOpenURL([NSURL URLWithString:[NSString stringWithFormat:@"%@://show", kKayokoURLScheme]], nil);
}

#pragma mark - SpringBoard URL 分发

CHOptimizedMethod2(self, BOOL, SpringBoard, application, UIApplication *, application, handleOpenURL, NSURL *, url) {
    if (KayokoIsTriggerURL(url)) {
        KayokoShowPanel(url);
        return YES;
    }
    return CHSuper2(SpringBoard, application, application, handleOpenURL, url);
}

CHOptimizedMethod3(self, BOOL, SpringBoard, application, UIApplication *, application, openURL, NSURL *, url, options, id, options) {
    if (KayokoIsTriggerURL(url)) {
        KayokoShowPanel(url);
        return YES;
    }
    return CHSuper3(SpringBoard, application, application, openURL, url, options, options);
}

CHOptimizedMethod4(self, BOOL, SpringBoard, application, UIApplication *, application, openURL, NSURL *, url, sourceApplication,
                   id, source, annotation, id, annotation) {
    if (KayokoIsTriggerURL(url)) {
        KayokoShowPanel(url);
        return YES;
    }
    return CHSuper4(SpringBoard, application, application, openURL, url, sourceApplication, source, annotation, annotation);
}

CHOptimizedMethod1(self, BOOL, SpringBoard, applicationOpenURL, NSURL *, url) {
    if (KayokoIsTriggerURL(url)) {
        KayokoShowPanel(url);
        return YES;
    }
    return CHSuper1(SpringBoard, applicationOpenURL, url);
}

CHOptimizedMethod2(self, BOOL, SpringBoard, applicationOpenURL, NSURL *, url, publicURLsOnly, BOOL, only) {
    if (KayokoIsTriggerURL(url)) {
        KayokoShowPanel(url);
        return YES;
    }
    return CHSuper2(SpringBoard, applicationOpenURL, url, publicURLsOnly, only);
}

CHOptimizedMethod8(self, BOOL, SpringBoard, applicationOpenURL, NSURL *, url, withApplication, id, application, sender, id, sender,
                   publicURLsOnly, BOOL, only, animating, BOOL, animating, needsConfirm, BOOL, confirm, options, id, options,
                   windowContext, id, context) {
    if (KayokoIsTriggerURL(url)) {
        KayokoShowPanel(url);
        return YES;
    }
    return CHSuper8(SpringBoard, applicationOpenURL, url, withApplication, application, sender, sender, publicURLsOnly, only,
                    animating, animating, needsConfirm, confirm, options, options, windowContext, context);
}

#pragma mark - 快捷指令：带 URL 的启动请求

CHOptimizedMethod5(self, void, FBSystemService, openApplication, id, application, withOptions, id, options, originator, id, originator,
                   requestID, unsigned int, requestID, completion, id, completion) {
    NSURL *URL = nil;
    @try {
        URL = [options respondsToSelector:@selector(url)] ? [options performSelector:@selector(url)] : nil;
    } @catch (__unused NSException *exception) {
        URL = nil;
    }

    if (KayokoIsTriggerURL(URL)) {
        KayokoShowPanel(URL);
        if (completion) {
            ((void (^)(id, id))completion)(nil, nil);
        }
        return;
    }

    CHSuper5(FBSystemService, openApplication, application, withOptions, options, originator, originator, requestID,
             requestID, completion, completion);
}

#pragma mark - Install

__attribute__((constructor)) static void KayokoURLDispatchHooksEntry(void) {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          Class boardClass = NSClassFromString(@"SpringBoard");
          if (boardClass) {
              CHLoadClass_(&SpringBoard$, boardClass);
              if ([boardClass instancesRespondToSelector:@selector(application:handleOpenURL:)]) {
                  CHHook2(SpringBoard, application, handleOpenURL);
              }
              if ([boardClass instancesRespondToSelector:@selector(application:openURL:options:)]) {
                  CHHook3(SpringBoard, application, openURL, options);
              }
              if ([boardClass instancesRespondToSelector:@selector(application:openURL:sourceApplication:annotation:)]) {
                  CHHook4(SpringBoard, application, openURL, sourceApplication, annotation);
              }
              if ([boardClass instancesRespondToSelector:@selector(applicationOpenURL:)]) {
                  CHHook1(SpringBoard, applicationOpenURL);
              }
              if ([boardClass instancesRespondToSelector:@selector(applicationOpenURL:publicURLsOnly:)]) {
                  CHHook2(SpringBoard, applicationOpenURL, publicURLsOnly);
              }
              if ([boardClass instancesRespondToSelector:@selector(applicationOpenURL:withApplication:sender:publicURLsOnly:animating:needsConfirm:options:windowContext:)]) {
                  CHHook8(SpringBoard, applicationOpenURL, withApplication, sender, publicURLsOnly, animating, needsConfirm, options, windowContext);
              }
          }

          Class serviceClass = NSClassFromString(@"FBSystemService");
          if (serviceClass) {
              CHLoadClass_(&FBSystemService$, serviceClass);
              Method openMethod = class_getInstanceMethod(serviceClass, @selector(openApplication:withOptions:originator:requestID:completion:));
              if (openMethod && method_getNumberOfArguments(openMethod) == 7) {
                  CHHook5(FBSystemService, openApplication, withOptions, originator, requestID, completion);
              }
          }
        });
    }
}
