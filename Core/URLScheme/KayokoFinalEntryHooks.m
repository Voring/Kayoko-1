//
//  KayokoFinalEntryHooks.m
//  Kayoko
//
//  ScreenCore 自己也会 hook FBSystemService -openApplication:...（它存了原始 IMP），
//  于是它内部再调原始实现时会绕过我们的 openApplication 钩子，一路走到
//  FBSystemService -_reallyActivateApplication:...:withResult:（11 参，最终激活点）。
//  这里挂这个最终入口，并顺带补 UIApplication -openURL:（1 参旧接口）与
//  SBApplication -applicationOpenURL: 的观测。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(FBSystemService);
CHDeclareClass(UIApplication);
CHDeclareClass(SBApplication);

@interface FBSystemService : NSObject
- (void)_reallyActivateApplication:(id)application
                         requestID:(id)requestID
                           options:(id)options
                            source:(id)source
                    originalSource:(id)originalSource
                         isTrusted:(BOOL)isTrusted
                    sequenceNumber:(id)sequenceNumber
                         cacheGUID:(id)cacheGUID
                 ourSequenceNumber:(id)ourSequenceNumber
                      ourCacheGUID:(id)ourCacheGUID
                        withResult:(id)result;
@end

@interface UIApplication : NSObject
- (BOOL)openURL:(NSURL *)url;
@end

@interface SBApplication : NSObject
- (void)applicationOpenURL:(NSURL *)url;
@end

static NSString *KayokoFinalDiagPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      path = [KayokoURLSchemeRequestDirectoryPath() stringByAppendingPathComponent:@"diag.txt"];
    });
    return path;
}

static void KayokoFinalDiag(NSString *line) {
    @autoreleasepool {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *entry = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
        NSString *path = KayokoFinalDiagPath();
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

static BOOL KayokoFinalIsOurs(NSURL *URL) {
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

static void KayokoFinalDeliver(NSURL *URL, NSString *source) {
    KayokoFinalDiag([NSString stringWithFormat:@"hit %@ url=%@", source, [URL absoluteString]]);
    NSString *all = [[[URL absoluteString] lowercaseString] stringByRemovingPercentEncoding] ?: @"";
    if ([all rangeOfString:@"diag"].location != NSNotFound) {
        NSString *body = [NSString stringWithContentsOfFile:KayokoFinalDiagPath()
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
        [UIPasteboard generalPasteboard].string =
            [NSString stringWithFormat:@"=== Kayoko URL diag (springboard) ===\n%@handled by SpringBoard at %@ (App 未被启动)\n",
                                       body ?: @"(diag.txt 为空)\n", [NSDate date]];
        return;
    }
    KayokoURLSchemeInterceptOpenURL([NSURL URLWithString:[NSString stringWithFormat:@"%@://show", kKayokoURLScheme]], nil);
}

CHOptimizedMethod11(self, void, FBSystemService, _reallyActivateApplication, id, application, requestID, id, requestID,
                    options, id, options, source, id, source, originalSource, id, originalSource, isTrusted, BOOL, isTrusted,
                    sequenceNumber, id, sequenceNumber, cacheGUID, id, cacheGUID, ourSequenceNumber, id, ourSequenceNumber,
                    ourCacheGUID, id, ourCacheGUID, withResult, id, result) {
    NSURL *URL = nil;
    @try {
        if ([options respondsToSelector:@selector(url)]) {
            URL = [options performSelector:@selector(url)];
        }
        if (![URL isKindOfClass:[NSURL class]]) {
            URL = nil;
        }
    } @catch (__unused NSException *exception) {
        URL = nil;
    }

    NSString *description = nil;
    @try {
        description = [NSString stringWithFormat:@"%@ %@", [application description], [options description]];
    } @catch (__unused NSException *exception) {
        description = nil;
    }
    if ([description rangeOfString:@"prefs" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [description rangeOfString:@"Preferences" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        KayokoFinalDiag([NSString stringWithFormat:@"probe reallyActivate url=%@ %@", [URL absoluteString], description]);
    }

    if (KayokoFinalIsOurs(URL)) {
        KayokoFinalDeliver(URL, @"FBSystemService._reallyActivate");
        if (result) {
            ((void (^)(id, id))result)(nil, nil);
        }
        return;
    }
    CHSuper11(FBSystemService, _reallyActivateApplication, application, requestID, requestID, options, options, source, source,
              originalSource, originalSource, isTrusted, isTrusted, sequenceNumber, sequenceNumber, cacheGUID, cacheGUID,
              ourSequenceNumber, ourSequenceNumber, ourCacheGUID, ourCacheGUID, withResult, result);
}

CHOptimizedMethod1(self, BOOL, UIApplication, openURL, NSURL *, url) {
    if (KayokoFinalIsOurs(url)) {
        KayokoFinalDeliver(url, @"UIApplication.openURL");
        return YES;
    }
    return CHSuper1(UIApplication, openURL, url);
}

CHOptimizedMethod1(self, void, SBApplication, applicationOpenURL, NSURL *, url) {
    KayokoFinalDiag([NSString stringWithFormat:@"probe SBApplication.applicationOpenURL url=%@", [url absoluteString]]);
    CHSuper1(SBApplication, applicationOpenURL, url);
}

__attribute__((constructor)) static void KayokoFinalEntryHooksEntry(void) {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          Class fbServiceClass = NSClassFromString(@"FBSystemService");
          if (fbServiceClass) {
              CHLoadClass_(&FBSystemService$, fbServiceClass);
              Method reallyMethod = class_getInstanceMethod(fbServiceClass, @selector(_reallyActivateApplication:requestID:options:source:originalSource:isTrusted:sequenceNumber:cacheGUID:ourSequenceNumber:ourCacheGUID:withResult:));
              if (reallyMethod && method_getNumberOfArguments(reallyMethod) == 13) {
                  CHHook11(FBSystemService, _reallyActivateApplication, requestID, options, source, originalSource, isTrusted,
                           sequenceNumber, cacheGUID, ourSequenceNumber, ourCacheGUID, withResult);
                  KayokoFinalDiag(@"install: FBSystemService._reallyActivate hook installed");
              } else {
                  KayokoFinalDiag(@"install: FBSystemService._reallyActivate 不存在");
              }
          }

          Class appClass = NSClassFromString(@"UIApplication");
          if ([appClass instancesRespondToSelector:@selector(openURL:)]) {
              CHLoadClass_(&UIApplication$, appClass);
              CHHook1(UIApplication, openURL);
              KayokoFinalDiag(@"install: UIApplication.openURL(1) hook installed");
          }

          Class sbAppClass = NSClassFromString(@"SBApplication");
          if ([sbAppClass instancesRespondToSelector:@selector(applicationOpenURL:)]) {
              CHLoadClass_(&SBApplication$, sbAppClass);
              CHHook1(SBApplication, applicationOpenURL);
              KayokoFinalDiag(@"install: SBApplication.applicationOpenURL hook installed");
          } else {
              KayokoFinalDiag(@"install: SBApplication.applicationOpenURL 不存在");
          }
        });
    }
}
