//
//  KayokoAppLaunchHooks.m
//  Kayoko
//
//  尝试在 SpringBoard 侧拦截“为 URL 启动 App”的请求，避免 kayoko:// 打开时
//  闪一下空白 App。同时把安装/触发/方法列表写入 diag.txt 供诊断。
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

static void KayokoAppLaunchDumpMethods(NSString *className, NSString *keywords) {
    Class cls = NSClassFromString(className);
    if (!cls) {
        KayokoAppLaunchDiag([NSString stringWithFormat:@"dump %@: class NOT found", className]);
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int index = 0; index < count; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        if (![keywords length] || [name rangeOfString:keywords options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [names addObject:name];
        }
    }
    free(methods);
    NSUInteger total = [names count];
    NSArray<NSString *> *shown = total > 24 ? [names subarrayWithRange:NSMakeRange(0, 24)] : names;
    KayokoAppLaunchDiag([NSString stringWithFormat:@"dump %@ (%lu/%u): %@", className, (unsigned long)total, count,
                                                   [shown componentsJoinedByString:@" | "]]);
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
        KayokoAppLaunchDumpMethods(@"FBSystemService", @"");
        KayokoAppLaunchDumpMethods(@"FBApplicationProcess", @"open|launch|url|activat");
        KayokoAppLaunchDumpMethods(@"FBWorkspace", @"open|launch|url|activat");
        KayokoAppLaunchDumpMethods(@"SBMainWorkspace", @"open|launch|url|activat");
        KayokoAppLaunchDumpMethods(@"LSApplicationWorkspace", @"open|url|launch");
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
