//
//  KayokoURLSchemeBridge.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 运行在非 SpringBoard 进程（App、键盘扩展等）里的请求通道。
///
/// 由于 iOS 的 URL scheme 由 LaunchServices 决定，未在 LaunchServices 注册的 scheme 不会
/// 被路由到任何进程，因此本插件在注入到各 App 进程后，会把 kayoko:// 请求写进共享 plist
/// 并通知 SpringBoard 中的 KayokoCore 执行，再把执行结果回传。
@interface KayokoURLSchemeBridge : NSObject

+ (instancetype)sharedBridge;

/// 同步发送请求并等待 SpringBoard 的响应（最长等待 5 秒）。
///
/// @param URL kayoko:// 形式的 URL，其他 scheme 会直接返回失败。
/// @param source 调用方标识，仅用于日志与请求追踪，可为空。
/// @return SpringBoard 是否成功执行了该请求。
- (BOOL)sendURL:(NSURL *)URL source:(nullable NSString *)source error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
