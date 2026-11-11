//
//  KayokoURLProbeHooks.m
//  Kayoko
//
//  ScreenCore 的 ARC 菜单唤起时，前面挂的 FBSystemService / LS -openURL: / UIApplication
//  都收不到（diag 里一条 hit 都没有）。它 dylib 里出现的是这些更底层的入口：
//    LSApplicationWorkspace -_openURLCore:display:animating:activationSettings:origin:withResult:
//    FBSSystemService        -openURL:application:options:clientPort:withResult:
//  这版把这几个也挂上，并把“打开设置 App”的请求原样记进 diag，用来确认它到底从哪进来。
//

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "../../Shared/URLScheme/KayokoURLSchemeProtocol.h"
#import "KayokoURLSchemeHandler.h"

CHDeclareClass(LSApplicationWorkspace);
CHDeclareClass(FBSSystemService);

@interface LSApplicationWorkspace : NSObject
- (void)_openURLCore:(NSURL *)url
              display:(id)display
            animating:(BOOL)animating
   activationSettings:(id)settings
               origin:(id)origin
           withResult:(id)result;
- (BOOL)openApplication:(id)application withOptions:(id)options error:(id *)error;
@end

@interface FBSSystemService : NSObject
- (void)openURL:(NSURL *)url
     application:(id)application
         options:(id)options
      clientPort:(id)clientPort
      withResult:(id)result;
@end

static NSString *KayokoProbeDiagPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      path = [KayokoURLSchemeRequestDirectoryPath() stringByAppendingPathComponent:@"diag.txt"];
    });
    return path;
}

static void KayokoProbeDiag(NSString *line) {
    @autoreleasepool {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *entry = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
        NSString *path = KayokoProbeDiagPath();
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

static BOOL KayokoProbeIsOurs(NSURL *URL) {
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

static void KayokoProbeDeliver(NSURL *URL, NSString *source) {
    KayokoProbeDiag([NSString stringWithFormat:@"hit %@ url=%@", source, [URL absoluteString]]);
    NSString *all = [[[URL absoluteString] lowercaseString] stringByRemovingPercentEncoding] ?: @"";
    if ([all rangeOfString:@"diag"].location != NSNotFound) {
        NSString *body = [NSString stringWithContentsOfFile:KayokoProbeDiagPath()
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
        [UIPasteboard generalPasteboard].string =
            [NSString stringWithFormat:@"=== Kayoko URL diag (springboard) ===\n%@handled by SpringBoard at %@ (App 未被启动)\n",
                                       body ?: @"(diag.txt 为空)\n", [NSDate date]];
        return;
    }
    KayokoURLSchemeInterceptOpenURL([NSURL URLWithString:[NSString stringWithFormat:@"%@://show", kKayokoURLScheme]], nil);
}

CHOptimizedMethod6(self, void, LSApplicationWorkspace, _openURLCore, NSURL *, url, display, id, display, animating, BOOL, animating,
                   activationSettings, id, settings, origin, id, origin, withResult, id, result) {
    if (KayokoProbeIsOurs(url)) {
        KayokoProbeDeliver(url, @"LSWorkspace._openURLCore");
        if (result) {
            ((void (^)(id, id))result)(nil, nil);
        }
        return;
    }
    CHSuper6(LSApplicationWorkspace, _openURLCore, url, display, display, animating, animating, activationSettings, settings,
             origin, origin, withResult, result);
}

CHOptimizedMethod5(self, void, FBSSystemService, openURL, NSURL *, url, application, id, application, options, id, options,
                   clientPort, id, clientPort, withResult, id, result) {
    if (KayokoProbeIsOurs(url)) {
        KayokoProbeDeliver(url, @"FBSSystemService.openURL");
        if (result) {
            ((void (^)(id, id))result)(nil, nil);
        }
        return;
    }
    CHSuper5(FBSSystemService, openURL, url, application, application, options, options, clientPort, clientPort,
             withResult, result);
}

CHOptimizedMethod3(self, BOOL, LSApplicationWorkspace, openApplication, id, application, withOptions, id, options, error, id *, error) {
    NSString *description = nil;
    @try {
        description = [NSString stringWithFormat:@"%@ %@", [application description], [options description]];
    } @catch (__unused NSException *exception) {
        description = nil;
    }
    if ([description rangeOfString:@"prefs" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [description rangeOfString:@"Preferences" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        KayokoProbeDiag([NSString stringWithFormat:@"probe LS openApplication: %@", description]);
    }
    return CHSuper3(LSApplicationWorkspace, openApplication, application, withOptions, options, error, error);
}

__attribute__((constructor)) static void KayokoURLProbeHooksEntry(void) {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
          Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
          if (workspaceClass) {
              CHLoadClass_(&LSApplicationWorkspace$, workspaceClass);
              Method urlMethod = class_getInstanceMethod(workspaceClass, @selector(_openURLCore:display:animating:activationSettings:origin:withResult:));
              if (urlMethod && method_getNumberOfArguments(urlMethod) == 8) {
                  CHHook6(LSApplicationWorkspace, _openURLCore, display, animating, activationSettings, origin, withResult);
                  KayokoProbeDiag(@"install: LS._openURLCore hook installed");
              } else {
                  KayokoProbeDiag(@"install: LS._openURLCore 不存在");
              }
              if (class_getInstanceMethod(workspaceClass, @selector(openApplication:withOptions:error:))) {
                  CHHook3(LSApplicationWorkspace, openApplication, withOptions, error);
                  KayokoProbeDiag(@"install: LS.openApplication probe installed");
              }
          }
          Class systemServiceClass = NSClassFromString(@"FBSSystemService");
          if (systemServiceClass) {
              CHLoadClass_(&FBSSystemService$, systemServiceClass);
              Method openMethod = class_getInstanceMethod(systemServiceClass, @selector(openURL:application:options:clientPort:withResult:));
              if (openMethod && method_getNumberOfArguments(openMethod) == 7) {
                  CHHook5(FBSSystemService, openURL, application, options, clientPort, withResult);
                  KayokoProbeDiag(@"install: FBSSystemService.openURL hook installed");
              } else {
                  KayokoProbeDiag(@"install: FBSSystemService.openURL 不存在");
              }
          } else {
              KayokoProbeDiag(@"install: FBSSystemService 类不存在");
          }
        });
    }
}
