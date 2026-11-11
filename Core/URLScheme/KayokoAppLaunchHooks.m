//
//  KayokoAppLaunchHooks.m
//  Kayoko
//
//  SpringBoard 侧接管 kayoko://，避免拉起占位的 KayokoURLHandler.app（空白界面闪现）。
//
//  两个入口：
//  - LSApplicationWorkspace -openURL:/openURL:withOptions:/openSensitiveURL:withOptions:
//    （ARC 菜单、分屏插件等常驻 SpringBoard 的调用方走这里）
//  - FBSystemService -openApplication:withOptions:originator:requestID:completion:
//    （Shortcuts 等经 SpringBoard 的请求走这里）
//
//  kayoko://diag 由本层直接写剪贴板，不启动 App。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(FBSystemService);
CHDeclareClass(LSApplicationWorkspace);

@interface LSApplicationWorkspace : NSObject
- (BOOL)openURL:(NSURL *)url;
- (BOOL)openURL:(NSURL *)url withOptions:(id)options;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options;
@end

@interface FBSystemService : NSObject
- (void)openApplication:(id)application
            withOptions:(id)options
              originator:(id)originator
                requestID:(unsigned int)requestID
              completion:(id)completion;
@end

static NSString *KayokoAppLaunchDiagPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSString *dir = KayokoURLSchemeRequestDirectoryPath();
      path = [dir stringByAppendingPathComponent:@"diag.txt"];
    });
    return path;
}

static void KayokoAppLaunchDiag(NSString *line) {
    @autoreleasepool {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *entry = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
        NSString *path = KayokoAppLaunchDiagPath();
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

static NSURL *KayokoURLFromOpenOptions(id options) {
    if (!options) {
        return nil;
    }
    @try {
        if ([options respondsToSelector:@selector(url)]) {
            NSURL *url = [options performSelector:@selector(url)];
            if ([url isKindOfClass:[NSURL class]]) {
                return url;
            }
        }
        NSDictionary *dict = [options valueForKey:@"dictionary"];
        if ([dict isKindOfClass:[NSDictionary class]]) {
            NSURL *url = dict[@"URL"] ?: dict[@"url"];
            if ([url isKindOfClass:[NSURL class]]) {
                return url;
            }
            if ([url isKindOfClass:[NSString class]]) {
                return [NSURL URLWithString:(NSString *)url];
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static void KayokoAppLaunchCopyDiagToPasteboard(void) {
    NSString *body = [NSString stringWithContentsOfFile:KayokoAppLaunchDiagPath()
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    NSString *text = [NSString stringWithFormat:@"=== Kayoko URL diag (springboard) ===\n%@"
                                                @"handled by SpringBoard at %@ (App 未被启动)\n",
                                                body ?: @"(diag.txt 为空)\n", [NSDate date]];
    [UIPasteboard generalPasteboard].string = text;
}

static BOOL KayokoHandleURLIfNeeded(NSURL *URL, NSString *source) {
    if (!KayokoURLSchemeIsKayokoURL(URL)) {
        return NO;
    }
    NSString *hostOrPath = [[[URL host] ?: @"" lowercaseString] stringByAppendingString:[[URL path] lowercaseString]];
    KayokoAppLaunchDiag([NSString stringWithFormat:@"hit %@ url=%@", source, [URL absoluteString]]);
    if ([hostOrPath rangeOfString:@"diag"].location != NSNotFound) {
        KayokoAppLaunchCopyDiagToPasteboard();
    } else {
        KayokoURLSchemeInterceptOpenURL(URL, nil);
    }
    return YES;
}

#pragma mark - LSApplicationWorkspace

CHOptimizedMethod1(self, BOOL, LSApplicationWorkspace, openURL, NSURL *, url) {
    if (KayokoHandleURLIfNeeded(url, @"LSWorkspace.openURL")) {
        return YES;
    }
    return CHSuper1(LSApplicationWorkspace, openURL, url);
}

CHOptimizedMethod2(self, BOOL, LSApplicationWorkspace, openURL, NSURL *, url, withOptions, id, options) {
    if (KayokoHandleURLIfNeeded(url, @"LSWorkspace.openURL:withOptions:")) {
        return YES;
    }
    return CHSuper2(LSApplicationWorkspace, openURL, url, withOptions, options);
}

CHOptimizedMethod2(self, BOOL, LSApplicationWorkspace, openSensitiveURL, NSURL *, url, withOptions, id, options) {
    if (KayokoHandleURLIfNeeded(url, @"LSWorkspace.openSensitiveURL")) {
        return YES;
    }
    return CHSuper2(LSApplicationWorkspace, openSensitiveURL, url, withOptions, options);
}

#pragma mark - FBSystemService

CHOptimizedMethod5(self, void, FBSystemService, openApplication, id, application, withOptions, id, options, originator,
                   id, originator, requestID, unsigned int, requestID, completion, id, completion) {
    NSURL *URL = KayokoURLFromOpenOptions(options);

    if (KayokoURLSchemeIsKayokoURL(URL)) {
        KayokoHandleURLIfNeeded(URL, @"FBSystemService.openApplication");
        if (completion) {
            ((void (^)(id, id))completion)(nil, nil);
        }
        return;
    }

    NSString *appDescription = nil;
    @try {
        appDescription = [application description];
    } @catch (__unused NSException *exception) {
        appDescription = nil;
    }
    if ([appDescription rangeOfString:@"KayokoURLHandler" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [appDescription rangeOfString:@"mlgm.kayoko" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        // 不带 kayoko:// 的启动请求：这才是空白占位 App 的来源，直接拦掉。
        KayokoAppLaunchDiag(@"blocked: 无 URL 的 handler App 启动请求");
        if (completion) {
            ((void (^)(id, id))completion)(nil, nil);
        }
        return;
    }

    CHSuper5(FBSystemService, openApplication, application, withOptions, options, originator, originator, requestID,
             requestID, completion, completion);
}

#pragma mark - Install

static void KayokoInstallLSWorkspaceHooks(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        KayokoAppLaunchDiag(@"install: LSApplicationWorkspace 类不存在");
        return;
    }
    CHLoadClass_(&LSApplicationWorkspace$, workspaceClass);

    NSInteger hooked = 0;
    if (class_getInstanceMethod(workspaceClass, @selector(openURL:))) {
        CHHook1(LSApplicationWorkspace, openURL);
        hooked++;
    }
    if (class_getInstanceMethod(workspaceClass, @selector(openURL:withOptions:))) {
        CHHook2(LSApplicationWorkspace, openURL, withOptions);
        hooked++;
    }
    if (class_getInstanceMethod(workspaceClass, @selector(openSensitiveURL:withOptions:))) {
        CHHook2(LSApplicationWorkspace, openSensitiveURL, withOptions);
        hooked++;
    }
    KayokoAppLaunchDiag([NSString stringWithFormat:@"install: LSApplicationWorkspace 挂钩 %ld 个", (long)hooked]);
}

static void KayokoInstallAppLaunchHooks(void) {
    Class systemServiceClass = NSClassFromString(@"FBSystemService");
    if (!systemServiceClass) {
        KayokoAppLaunchDiag(@"install: FBSystemService 尚未加载");
        return;
    }
    CHLoadClass_(&FBSystemService$, systemServiceClass);

    Method openMethod = class_getInstanceMethod(systemServiceClass,
                                                @selector(openApplication:withOptions:originator:requestID:completion:));
    if (openMethod && method_getNumberOfArguments(openMethod) == 7) {
        CHHook5(FBSystemService, openApplication, withOptions, originator, requestID, completion);
        KayokoAppLaunchDiag(@"install: openApplication hook installed");
    } else {
        KayokoAppLaunchDiag(@"install: openApplication NOT hooked");
    }
}

__attribute__((constructor)) static void KayokoAppLaunchHooksEntry(void) {
    @autoreleasepool {
        // 只挂钩一次：重复 CHHook 同一方法会递归/竞态，导致 SpringBoard 崩溃。
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          KayokoInstallLSWorkspaceHooks();
          KayokoInstallAppLaunchHooks();
        });
    }
}
