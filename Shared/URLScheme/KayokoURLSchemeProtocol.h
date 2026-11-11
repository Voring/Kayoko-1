//
//  KayokoURLSchemeProtocol.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 对外暴露的 URL scheme，形如 kayoko://show。
static NSString *const kKayokoURLScheme = @"kayoko";

/// 错误码。
typedef NS_ENUM(NSInteger, KayokoURLSchemeErrorCode) {
    KayokoURLSchemeErrorCodeUnknown = 0,
    KayokoURLSchemeErrorCodeTimedOut = 1,
    KayokoURLSchemeErrorCodeInvalidResponse = 2,
    KayokoURLSchemeErrorCodeTransportFailure = 3,
};

/// 构造协议层使用的 NSError。
FOUNDATION_EXPORT NSError *KayokoURLSchemeMakeError(NSInteger code, NSString *message);

/// 判断 URL 是否使用 Kayoko 的 scheme。
FOUNDATION_EXPORT BOOL KayokoURLSchemeIsKayokoURL(NSURL *_Nullable URL);

NS_ASSUME_NONNULL_END
