//
//  KayokoAppLaunchHooks.m
//  Kayoko
//
//  在 SpringBoard 侧拦截“为 URL 启动 App”的请求，避免 kayoko:// 打开时
//  闪一下空白 App。
//
//  iOS 16.4.1 上 FBSystemService 的真实入口是：
//  - openApplication:withOptions:originator:requestID:completion:
//  URL 藏在 options.url 里。拦截后就地执行面板动作，不放行原始启动请求。
//
//  kayoko://diag 也在这一层直接处理：把诊断信息写进系统剪贴板，不启动 App。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(FBSystemService);

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

CHOptimizedMethod5(self, void, FBSystemService, openApplication, id, application, withOptions, id, options, originator,
                   id, originator, requestID, unsigned int, requestID, completion, id, completion) {
    NSURL *URL = KayokoURLFromOpenOptions(options);

    if (KayokoURLSchemeIsKayokoURL(URL)) {
        KayokoAppLaunchDiag([NSString stringWithFormat:@"hit openApplication url=%@", [URL absoluteString]]);

        // kayoko://diag：完全不启动 App，直接把诊断信息写进系统剪贴板，
        // 这样在“拦截已生效”的情况下也能把状态回传。
        NSString *hostOrPath = [[[URL host] ?: @"" lowercaseString] stringByAppendingString:[[URL path] lowercaseString]];
        if ([hostOrPath rangeOfString:@"diag"].location != NSNotFound) {
            NSString *body = [NSString stringWithContentsOfFile:KayokoAppLaunchDiagPath()
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
            NSString *text = [NSString stringWithFormat:@"=== Kayoko URL diag (springboard) ===\n%@"
                                                        @"handled by SpringBoard at %@ (App 未被启动)\n",
                                                        body ?: @"(diag.txt 为空)\n", [NSDate date]];
            [UIPasteboard generalPasteboard].string = text;
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
    if (openMethod) {
        const char *types = method_getTypeEncoding(openMethod);
        KayokoAppLaunchDiag([NSString stringWithFormat:@"install: openApplication method argc=%u type=%s",
                                                       method_getNumberOfArguments(openMethod),
                                                       types ? types : "(null)"]);
        if (method_getNumberOfArguments(openMethod) == 7) {
            CHHook5(FBSystemService, openApplication, withOptions, originator, requestID, completion);
            KayokoAppLaunchDiag(@"install: hook installed");
        } else {
            KayokoAppLaunchDiag(@"install: argc mismatch, hook skipped");
        }
    } else {
        KayokoAppLaunchDiag(@"install: openApplication method NOT found");
    }
}

__attribute__((constructor)) static void KayokoAppLaunchHooksEntry(void) {
    @autoreleasepool {
        if (NSClassFromString(@"FBSystemService") == nil) {
            return;
        }
        KayokoInstallAppLaunchHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         KayokoInstallAppLaunchHooks();
                       });
    }
}
