//
//  KayokoURLSchemeProtocol.m
//  Kayoko
//

#import "KayokoURLSchemeProtocol.h"

NSString *const kKayokoURLSchemeErrorDomain = @"com.mlgm.kayoko.url-scheme";

BOOL KayokoURLSchemeIsKayokoURL(NSURL *URL) {
    if (![URL isKindOfClass:[NSURL class]]) {
        return NO;
    }
    NSString *scheme = [[URL scheme] lowercaseString];
    return [scheme isEqualToString:kKayokoURLScheme];
}

NSError *KayokoURLSchemeMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:kKayokoURLSchemeErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey : message ?: @""}];
}
