//
//  KayokoURLSchemeHooks.m
//  Kayoko
//

#define CHUseSubstrate

#import "KayokoURLSchemeHooks.h"
#import "../Shared/KayokoHookValidation.h"
#import "../Shared/URLScheme/KayokoURLSchemeBridge.h"
#import "../Shared/URLScheme/KayokoURLSchemeProtocol.h"

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

typedef void (^KayokoURLSchemeOpenURLCompletion)(BOOL success);

CHDeclareClass(UIApplication);
CHDeclareClass(LSApplicationWorkspace);

#pragma mark - Forwarding

/// 命中 kayoko:// 时返回 YES，并在后台把请求交给 SpringBoard 执行。
static BOOL KayokoURLSchemeForwardOpenURL(NSURL *URL, NSString *source,
                                          KayokoURLSchemeOpenURLCompletion completionHandler) {
    if (!KayokoURLSchemeIsKayokoURL(URL)) {
        return NO;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *error = nil;
      BOOL handled = [[KayokoURLSchemeBridge sharedBridge] sendURL:URL source:source error:&error];
      if (!handled) {
          NSLog(@"Kayoko: URL scheme %@ failed: %@", [URL absoluteString], error);
      }
      if (!completionHandler) {
          return;
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        completionHandler(handled);
      });
    });

    return YES;
}

#pragma mark - UIApplication Hooks

CHOptimizedMethod3(self, void, UIApplication, openURL, NSURL *, URL, options, NSDictionary *, options,
                   completionHandler, KayokoURLSchemeOpenURLCompletion, completionHandler) {
    if (KayokoURLSchemeForwardOpenURL(URL, @"ui-application", completionHandler)) {
        return;
    }
    CHSuper3(UIApplication, openURL, URL, options, options, completionHandler, completionHandler);
}

CHOptimizedMethod1(self, BOOL, UIApplication, openURL, NSURL *, URL) {
    if (KayokoURLSchemeForwardOpenURL(URL, @"ui-application", nil)) {
        return YES;
    }
    return CHSuper1(UIApplication, openURL, URL);
}

#pragma mark - LaunchServices Hooks

CHOptimizedMethod2(self, BOOL, LSApplicationWorkspace, openURL, NSURL *, URL, withOptions, NSDictionary *, options) {
    if (KayokoURLSchemeForwardOpenURL(URL, @"ls-application-workspace", nil)) {
        return YES;
    }
    return CHSuper2(LSApplicationWorkspace, openURL, URL, withOptions, options);
}

CHOptimizedMethod2(self, BOOL, LSApplicationWorkspace, openSensitiveURL, NSURL *, URL, withOptions,
                   NSDictionary *, options) {
    if (KayokoURLSchemeForwardOpenURL(URL, @"ls-application-workspace", nil)) {
        return YES;
    }
    return CHSuper2(LSApplicationWorkspace, openSensitiveURL, URL, withOptions, options);
}

#pragma mark - Installer

@implementation KayokoURLSchemeHookInstaller

+ (void)installHooks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      Class applicationClass = NSClassFromString(@"UIApplication");
      if (applicationClass) {
          CHLoadClass(UIApplication);
          if (KayokoHookMethodMatches(applicationClass, @selector(openURL:options:completionHandler:), "v@:@@@?")) {
              CHHook3(UIApplication, openURL, options, completionHandler);
          }
          if (KayokoHookMethodMatches(applicationClass, @selector(openURL:), "B@:@")) {
              CHHook1(UIApplication, openURL);
          }
      }

      Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
      if (workspaceClass) {
          CHLoadClass_(&LSApplicationWorkspace$, workspaceClass);
          if (KayokoHookMethodMatches(workspaceClass, @selector(openURL:withOptions:), "B@:@@")) {
              CHHook2(LSApplicationWorkspace, openURL, withOptions);
          }
          if (KayokoHookMethodMatches(workspaceClass, @selector(openSensitiveURL:withOptions:), "B@:@@")) {
              CHHook2(LSApplicationWorkspace, openSensitiveURL, withOptions);
          }
      }
    });
}

@end
