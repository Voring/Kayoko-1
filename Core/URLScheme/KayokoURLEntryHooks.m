//
//  KayokoURLEntryHooks.m
//  Kayoko
//
//  ScreenCore 这类常驻 SpringBoard 的插件，ARC 菜单唤起时并不经过 FBSystemService，
//  也不走 LSApplicationWorkspace -openURL:，而是进 SBMainWorkspace 的 _openURLCore: 一族。
//  这里补挂这些更深的入口。命中后直接把 Prefs:root=Kayoko_* 转成面板调用。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(SBMainWorkspace);
CHDeclareClass(UIApplication);

@interface SBMainWorkspace : NSObject
- (void)_openURLCore:(NSURL *)url
              display:(id)display
            animating:(BOOL)animating
   activationSettings:(id)settings
               origin:(id)origin
           withResult:(id)result;
- (void)_handleOpenApplicationRequest:(id)request
                               options:(id)options
                    activationSettings:(id)settings
                                origin:(id)origin
                            withResult:(id)result;
@end

static NSString *KayokoEntryDiagPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      path = [KayokoURLSchemeRequestDirectoryPath() stringByAppendingPathComponent:@"diag.txt"];
    });
    return path;
}

static void KayokoEntryDiag(NSString *line) {
    @autoreleasepool {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *entry = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
        NSString *path = KayokoEntryDiagPath();
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

static NSString *KayokoEntryQueryValue(NSString *rest, NSString *key) {
    for (NSString *pair in [rest componentsSeparatedByString:@"&"]) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if ([kv count] < 2) {
            continue;
        }
        NSString *name = [[kv[0] stringByRemovingPercentEncoding] ?: kv[0] lowercaseString];
        if (![name isEqualToString:[key lowercaseString]]) {
            continue;
        }
        return [kv[1] stringByRemovingPercentEncoding] ?: kv[1];
    }
    return nil;
}

static NSString *KayokoEntryActionFromPrefsURL(NSURL *URL) {
    NSString *scheme = [[URL scheme] lowercaseString];
    if (!([scheme isEqualToString:@"prefs"] || [scheme isEqualToString:@"app-prefs"])) {
        return nil;
    }
    NSString *rest = [URL resourceSpecifier] ?: @"";
    while ([rest hasPrefix:@"/"]) {
        rest = [rest substringFromIndex:1];
    }
    NSString *root = KayokoEntryQueryValue(rest, @"root");
    if ([root length] == 0) {
        NSString *all = [URL absoluteString] ?: @"";
        NSRange range = [all rangeOfString:@"root=" options:NSCaseInsensitiveSearch];
        if (range.location == NSNotFound) {
            return nil;
        }
        root = [all substringFromIndex:NSMaxRange(range)];
        NSRange amp = [root rangeOfString:@"&"];
        if (amp.location != NSNotFound) {
            root = [root substringToIndex:amp.location];
        }
    }
    NSString *value = [root lowercaseString] ?: @"";
    if ([value rangeOfString:@"kayoko"].location == NSNotFound || [value isEqualToString:@"kayoko"]) {
        return nil;
    }
    return [value rangeOfString:@"diag"].location != NSNotFound ? @"diag" : @"show";
}

static BOOL KayokoEntryHandleURL(NSURL *URL, NSString *source) {
    NSString *action = nil;
    if (KayokoURLSchemeIsKayokoURL(URL)) {
        action = [[URL host] lowercaseString] ?: @"show";
    } else {
        action = KayokoEntryActionFromPrefsURL(URL);
    }
    if ([action length] == 0) {
        return NO;
    }

    KayokoEntryDiag([NSString stringWithFormat:@"hit %@ url=%@", source, [URL absoluteString]]);
    if ([action rangeOfString:@"diag"].location != NSNotFound) {
        NSString *body = [NSString stringWithContentsOfFile:KayokoEntryDiagPath()
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
        [UIPasteboard generalPasteboard].string =
            [NSString stringWithFormat:@"=== Kayoko URL diag (springboard) ===\n%@handled by SpringBoard at %@ (App 未被启动)\n",
                                       body ?: @"(diag.txt 为空)\n", [NSDate date]];
        return YES;
    }
    KayokoURLSchemeInterceptOpenURL([NSURL URLWithString:[NSString stringWithFormat:@"%@://show", kKayokoURLScheme]], nil);
    return YES;
}

CHOptimizedMethod6(self, void, SBMainWorkspace, _openURLCore, NSURL *, url, display, id, display, animating, BOOL, animating,
                   activationSettings, id, settings, origin, id, origin, withResult, id, result) {
    if (KayokoEntryHandleURL(url, @"SBMainWorkspace._openURLCore")) {
        if (result) {
            ((void (^)(id, id))result)(nil, nil);
        }
        return;
    }
    CHSuper6(SBMainWorkspace, _openURLCore, url, display, display, animating, animating, activationSettings, settings,
             origin, origin, withResult, result);
}

CHOptimizedMethod5(self, void, SBMainWorkspace, _handleOpenApplicationRequest, id, request, options, id, options,
                   activationSettings, id, settings, origin, id, origin, withResult, id, result) {
    NSURL *URL = nil;
    @try {
        URL = [options respondsToSelector:@selector(url)] ? [options performSelector:@selector(url)] : nil;
    } @catch (__unused NSException *exception) {
        URL = nil;
    }
    if ([URL isKindOfClass:[NSURL class]] && KayokoEntryHandleURL(URL, @"SBMainWorkspace.handleOpenApplicationRequest")) {
        if (result) {
            ((void (^)(id, id))result)(nil, nil);
        }
        return;
    }
    CHSuper5(SBMainWorkspace, _handleOpenApplicationRequest, request, options, options, activationSettings, settings, origin,
             origin, withResult, result);
}

CHOptimizedMethod3(self, void, UIApplication, openURL, NSURL *, url, options, id, options, completionHandler, id, handler) {
    if (KayokoEntryHandleURL(url, @"UIApplication.openURL")) {
        if (handler) {
            ((void (^)(BOOL))handler)(YES);
        }
        return;
    }
    CHSuper3(UIApplication, openURL, url, options, options, completionHandler, handler);
}

__attribute__((constructor)) static void KayokoURLEntryHooksEntry(void) {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          Class workspaceClass = NSClassFromString(@"SBMainWorkspace");
          if (workspaceClass) {
              CHLoadClass_(&SBMainWorkspace$, workspaceClass);
              Method urlMethod = class_getInstanceMethod(workspaceClass, @selector(_openURLCore:display:animating:activationSettings:origin:withResult:));
              if (urlMethod && method_getNumberOfArguments(urlMethod) == 8) {
                  CHHook6(SBMainWorkspace, _openURLCore, display, animating, activationSettings, origin, withResult);
                  KayokoEntryDiag(@"install: SBMainWorkspace._openURLCore hook installed");
              } else {
                  KayokoEntryDiag(@"install: SBMainWorkspace._openURLCore 未挂上");
              }
              Method requestMethod = class_getInstanceMethod(workspaceClass, @selector(_handleOpenApplicationRequest:options:activationSettings:origin:withResult:));
              if (requestMethod && method_getNumberOfArguments(requestMethod) == 7) {
                  CHHook5(SBMainWorkspace, _handleOpenApplicationRequest, options, activationSettings, origin, withResult);
                  KayokoEntryDiag(@"install: SBMainWorkspace.handleOpenApplicationRequest hook installed");
              } else {
                  KayokoEntryDiag(@"install: SBMainWorkspace.handleOpenApplicationRequest 未挂上");
              }
          } else {
              KayokoEntryDiag(@"install: SBMainWorkspace 类不存在");
          }

          Class appClass = NSClassFromString(@"UIApplication");
          if ([appClass instancesRespondToSelector:@selector(openURL:options:completionHandler:)]) {
              CHLoadClass_(&UIApplication$, appClass);
              CHHook3(UIApplication, openURL, options, completionHandler);
              KayokoEntryDiag(@"install: UIApplication.openURL hook installed");
          } else {
              KayokoEntryDiag(@"install: UIApplication.openURL 未挂上");
          }
        });
    }
}
