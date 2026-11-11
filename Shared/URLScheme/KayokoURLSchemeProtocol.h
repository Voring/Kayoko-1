//
//  KayokoURLSchemeProtocol.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 对外暴露的 URL scheme，形如 kayoko://show。
static NSString *const kKayokoURLScheme = @"kayoko";

/// Core 与 Helper 之间传递请求/响应所使用的 Darwin 通知名。
static NSString *const kKayokoURLSchemeRequestNotificationName = @"com.mlgm.kayoko.url-scheme.request";
static NSString *const kKayokoURLSchemeResponseNotificationName = @"com.mlgm.kayoko.url-scheme.response";

/// 请求/响应 plist 的键名。
static NSString *const kKayokoURLSchemeMessageKeyRequestIdentifier = @"request_identifier";
static NSString *const kKayokoURLSchemeMessageKeyURL = @"url";
static NSString *const kKayokoURLSchemeMessageKeySource = @"source";
static NSString *const kKayokoURLSchemeMessageKeyHandled = @"handled";
static NSString *const kKayokoURLSchemeMessageKeyError = @"error";
static NSString *const kKayokoURLSchemeMessageKeyErrorDomain = @"domain";
static NSString *const kKayokoURLSchemeMessageKeyErrorCode = @"code";
static NSString *const kKayokoURLSchemeMessageKeyErrorMessage = @"message";

/// 错误域与错误码。
static NSString *const kKayokoURLSchemeErrorDomain = @"com.mlgm.kayoko.url-scheme";

typedef NS_ENUM(NSInteger, KayokoURLSchemeErrorCode) {
    KayokoURLSchemeErrorCodeUnknown = 0,
    KayokoURLSchemeErrorCodeTimedOut = 1,
    KayokoURLSchemeErrorCodeInvalidResponse = 2,
    KayokoURLSchemeErrorCodeTransportFailure = 3,
};

/// 请求/响应文件所在目录，与历史数据库同处一个数据目录。
FOUNDATION_EXPORT NSString *KayokoURLSchemeRequestDirectoryPath(void);
FOUNDATION_EXPORT NSString *KayokoURLSchemeRequestPath(void);
FOUNDATION_EXPORT NSString *KayokoURLSchemeResponsePath(void);

/// 判断 URL 是否使用 Kayoko 的 scheme。
FOUNDATION_EXPORT BOOL KayokoURLSchemeIsKayokoURL(NSURL *_Nullable URL);

/// 读写请求/响应 plist。
FOUNDATION_EXPORT NSDictionary<NSString *, id> *_Nullable KayokoURLSchemeReadMessage(NSString *path);
FOUNDATION_EXPORT BOOL KayokoURLSchemeWriteMessage(NSDictionary<NSString *, id> *message, NSString *path,
                                                   NSError *_Nullable *_Nullable error);

/// 构造协议层使用的 NSError。
FOUNDATION_EXPORT NSError *KayokoURLSchemeMakeError(KayokoURLSchemeErrorCode code, NSString *message);

NS_ASSUME_NONNULL_END
