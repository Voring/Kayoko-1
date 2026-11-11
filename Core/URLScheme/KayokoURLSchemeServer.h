//
//  KayokoURLSchemeServer.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 运行在 SpringBoard（KayokoCore）里的请求服务：
/// 监听 Darwin 通知 → 读取请求 plist → 执行 kayoko:// → 回写响应 plist 并通知调用方。
@interface KayokoURLSchemeServer : NSObject

+ (instancetype)sharedServer;

- (BOOL)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
