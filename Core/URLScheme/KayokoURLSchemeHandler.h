//
//  KayokoURLSchemeHandler.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, KayokoURLSchemeResult) {
    KayokoURLSchemeResultFailed = 0,
    KayokoURLSchemeResultSuccess = 1,
};

typedef void (^KayokoURLSchemeCompletion)(KayokoURLSchemeResult result, NSError *_Nullable error);

/// 供 -[UIApplication openURL:options:completionHandler:] 之类的调用点复用：
/// 命中 kayoko:// 时返回 YES 并异步执行，调用方不必再走系统 openURL。
typedef void (^KayokoURLSchemeOpenCompletion)(BOOL success);

@interface KayokoURLSchemeHandler : NSObject

+ (instancetype)sharedHandler;

/// 解析并执行一个 kayoko:// URL。
///
/// @param URL 待处理的 URL。
/// @param source 请求来源标识，便于日志排查。
/// @param completion 执行结果回调，始终在主线程调用。
/// @return URL 是否使用 kayoko scheme。返回 NO 时调用方应继续走原有逻辑。
- (BOOL)handleURL:(NSURL *)URL
           source:(nullable NSString *)source
       completion:(nullable KayokoURLSchemeCompletion)completion;

@end

/// 进程内直接调用（其他 SpringBoard 插件可通过 dlsym(RTLD_DEFAULT, "KayokoURLSchemeHandleURL") 获取）。
FOUNDATION_EXPORT BOOL KayokoURLSchemeHandleURL(NSURL *URL, NSString *_Nullable source);

/// openURL 拦截入口。
FOUNDATION_EXPORT BOOL KayokoURLSchemeInterceptOpenURL(NSURL *_Nullable URL,
                                                       KayokoURLSchemeOpenCompletion _Nullable completionHandler);

NS_ASSUME_NONNULL_END
