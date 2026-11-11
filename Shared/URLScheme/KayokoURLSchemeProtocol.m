//
//  KayokoURLSchemeProtocol.m
//  Kayoko
//

#import "KayokoURLSchemeProtocol.h"

#if !KAYOKO_STANDALONE_URL_HANDLER
#import <roothide.h>
#endif

#if KAYOKO_STANDALONE_URL_HANDLER
/// 独立 App（不在 jbroot 注入环境里，也没法加载 libroothide）时，直接从自身
/// bundle 位置推算 jbroot 根：…/.jbroot-XXXX/Applications/KayokoURLHandler.app
static NSString *KayokoStandaloneJBRootPath(void) {
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];          // …/Applications/KayokoURLHandler.app
    NSString *bundleParent = [bundlePath stringByDeletingLastPathComponent]; // …/Applications
    if ([[bundleParent lastPathComponent] isEqualToString:@"Applications"]) {
        return [bundleParent stringByDeletingLastPathComponent];
    }
    return nil;
}
#endif

NSString *KayokoURLSchemeRequestDirectoryPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if KAYOKO_STANDALONE_URL_HANDLER
      NSString *jbRoot = KayokoStandaloneJBRootPath();
      path = [jbRoot stringByAppendingString:@"/var/mobile/Library/com.mlgm.kayoko/url-scheme"];
#else
      path = jbroot(@"/var/mobile/Library/com.mlgm.kayoko/url-scheme");
#endif
    });
    return path;
}

NSString *KayokoURLSchemeRequestPath(void) {
    return [KayokoURLSchemeRequestDirectoryPath() stringByAppendingPathComponent:@"request.plist"];
}

NSString *KayokoURLSchemeResponsePath(void) {
    return [KayokoURLSchemeRequestDirectoryPath() stringByAppendingPathComponent:@"response.plist"];
}

BOOL KayokoURLSchemeIsKayokoURL(NSURL *URL) {
    if (![URL isKindOfClass:[NSURL class]]) {
        return NO;
    }

    NSString *scheme = [[URL scheme] lowercaseString];
    if ([scheme length] == 0) {
        return NO;
    }

    return [scheme isEqualToString:kKayokoURLScheme];
}
