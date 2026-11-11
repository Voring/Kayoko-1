//
//  KayokoAppLaunchHooks.m
//  Kayoko
//
//  SpringBoard 侧接管 kayoko:// 的 App 启动请求，避免闪一下空白 App。
//
//  iOS 16.4.1 上 FBSystemService 的入口：
//  - openApplication:withOptions:originator:requestID:completion:（Shortcuts 走这里）
//  - handleActions:source:withResult:（LaunchServices action，第三方插件常走这里）
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(FBSystemService);

@interface FBSystemService : NSObject
- (void)handleActions:(id)actions source:(id)source withResult:(id)result;
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
        NSString *path = KayokoAppLaunchDiagPath();
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *stamp = [formatter stringFromDate:[NSDate date]];
        NSString *entry = [NSString stringWithFormat:@"%@ %@\n", stamp, line];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [path stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:nil attributes:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) {
            @try {
                [handle seekToEndOfFile];
                [handle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
            } @catch (__unused NSException *exception) {
            }
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

// handleActions 收到的 payload 里如果带 kayoko URL，就地接管。
CHOptimizedMethod3(self, void, FBSystemService, handleActions, id, actions, source, id, source, withResult, id, result) {
    NSString *description = nil;
    @try {
        description = [actions description];
    } @catch (__unused NSException *exception) {
        description = nil;
    }
    if ([description rangeOfString:@"kayoko" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        KayokoAppLaunchDiag([NSString stringWithFormat:@"hit handleActions: %@", description]);
        NSURL *URL = nil;
        @try {
            NSRange range = [description rangeOfString:@"kayoko://"];
            if (range.location != NSNotFound) {
                NSString *tail = [description substringFromIndex:range.location];
                NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@"\"' <>,;)}\n"];
                NSRange stopRange = [tail rangeOfCharacterFromSet:stop];
                if (stopRange.location != NSNotFound) {
                    tail = [tail substringToIndex:stopRange.location];
                }
                URL = [NSURL URLWithString:tail];
            }
        } @catch (__unused NSException *exception) {
            URL = nil;
        }

        if (KayokoURLSchemeIsKayokoURL(URL)) {
            NSString *hostOrPath = [[[URL host] ?: @"" lowercaseString] stringByAppendingString:[[URL path] lowercaseString]];
            if ([hostOrPath rangeOfString:@"diag"].location != NSNotFound) {
                KayokoAppLaunchCopyDiagToPasteboard();
            } else {
                KayokoURLSchemeInterceptOpenURL(URL, nil);
            }
            if (result) {
                ((void (^)(id, id))result)(nil, nil);
            }
            return;
        }
    }
    CHSuper3(FBSystemService, handleActions, actions, source, source, withResult, result);
}

CHOptimizedMethod5(self, void, FBSystemService, openApplication, id, application, withOptions, id, options, originator,
                   id, originator, requestID, unsigned int, requestID, completion, id, completion) {
    NSURL *URL = KayokoURLFromOpenOptions(options);

    NSString *bundleID = nil;
    @try {
        bundleID = [application respondsToSelector:@selector(bundleIdentifier)] ? [application bundleIdentifier] : nil;
    } @catch (__unused NSException *exception) {
        bundleID = nil;
    }
    if ([bundleID hasPrefix:@"com.mlgm.kayoko"] || KayokoURLSchemeIsKayokoURL(URL)) {
        KayokoAppLaunchDiag([NSString stringWithFormat:@"call bid=%@ url=%@", bundleID ?: @"(nil)",
                                                       [URL absoluteString] ?: @"(nil)"]);
    }

    if (KayokoURLSchemeIsKayokoURL(URL)) {
        KayokoAppLaunchDiag([NSString stringWithFormat:@"hit openApplication url=%@", [URL absoluteString]]);

        NSString *hostOrPath = [[[URL host] ?: @"" lowercaseString] stringByAppendingString:[[URL path] lowercaseString]];
        if ([hostOrPath rangeOfString:@"diag"].location != NSNotFound) {
            KayokoAppLaunchCopyDiagToPasteboard();
            if (completion) {
                ((void (^)(id, id))completion)(nil, nil);
            }
            return;
        }

        KayokoURLSchemeInterceptOpenURL(URL, nil);
        if (completion) {
            ((void (^)(id, id))completion)(nil, nil);
        }
        return;
    }

    CHSuper5(FBSystemService, openApplication, application, withOptions, options, originator, originator, requestID,
             requestID, completion, completion);
}

static void KayokoInstallAppLaunchHooks(void) {
    Class systemServiceClass = NSClassFromString(@"FBSystemService");
    if (!systemServiceClass) {
        KayokoAppLaunchDiag(@"install: FBSystemService class NOT found");
        return;
    }

    CHLoadClass_(&FBSystemService$, systemServiceClass);

    SEL openSelector = @selector(openApplication:withOptions:originator:requestID:completion:);
    Method openMethod = class_getInstanceMethod(systemServiceClass, openSelector);
    if (openMethod && method_getNumberOfArguments(openMethod) == 7) {
        CHHook5(FBSystemService, openApplication, withOptions, originator, requestID, completion);
        KayokoAppLaunchDiag(@"install: openApplication hook installed");
    } else {
        KayokoAppLaunchDiag(@"install: openApplication NOT hooked");
    }

    SEL actionsSelector = @selector(handleActions:source:withResult:);
    Method actionsMethod = class_getInstanceMethod(systemServiceClass, actionsSelector);
    if (actionsMethod && method_getNumberOfArguments(actionsMethod) == 5) {
        CHHook3(FBSystemService, handleActions, source, withResult);
        KayokoAppLaunchDiag(@"install: handleActions hook installed");
    } else {
        KayokoAppLaunchDiag(@"install: handleActions NOT hooked");
    }
}

__attribute__((constructor)) static void KayokoAppLaunchHooksEntry(void) {
    @autoreleasepool {
        // 只挂钩一次。重复 CHHook 同一方法会形成递归/竞态，导致 SpringBoard 崩溃。
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          if (NSClassFromString(@"FBSystemService") == nil) {
              KayokoAppLaunchDiag(@"install: FBSystemService 尚未加载，跳过");
              return;
          }
          KayokoInstallAppLaunchHooks();
        });
    }
}
