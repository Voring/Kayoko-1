//
//  KayokoAppLaunchHooks.m
//  Kayoko
//
//  外部（快捷指令 / 其他 App / 终端）打开 kayoko:// 时，LaunchServices 会先把请求
//  交给 SpringBoard 去“启动”认领该 scheme 的 KayokoURLHandler.app，于是屏幕上会
//  闪一下空白 App。这里尝试在启动前接住。同时把安装/触发情况写入 diag.txt，
//  供 kayoko://diag 把信息贴到剪贴板回传。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(FBSystemService);

@interface FBSystemService : NSObject
- (void)activateApplication:(id)application
                  requestID:(unsigned int)requestID
                    options:(id)options
                     source:(id)source
             originalSource:(id)originalSource
                 withResult:(id)result;
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
        KayokoAppLaunchDiag([NSString stringWithFormat:@"hit activateApplication url=%@", [URL absoluteString]]);
        KayokoURLSchemeInterceptOpenURL(URL, nil);
        if (result) {
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
        KayokoAppLaunchDiag(@"install: FBSystemService class NOT found");
        return;
    }

    CHLoadClass_(&FBSystemService$, systemServiceClass);

    SEL activateSelector = @selector(activateApplication:requestID:options:source:originalSource:withResult:);
    Method activateMethod = class_getInstanceMethod(systemServiceClass, activateSelector);
    if (activateMethod) {
        const char *types = method_getTypeEncoding(activateMethod);
        KayokoAppLaunchDiag([NSString stringWithFormat:@"install: method found argc=%u type=%s",
                                                       method_getNumberOfArguments(activateMethod),
                                                       types ? types : "(null)"]);
        if (method_getNumberOfArguments(activateMethod) == 8) {
            CHHook6(FBSystemService, activateApplication, requestID, options, source, originalSource, withResult);
            KayokoAppLaunchDiag(@"install: hook installed");
        } else {
            KayokoAppLaunchDiag(@"install: argc mismatch, hook skipped");
        }
    } else {
        KayokoAppLaunchDiag(@"install: method NOT found");
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
