//
//  KayokoURLSchemeHooks.h
//  Kayoko
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 在 App / 键盘扩展等进程里拦截 openURL，把 kayoko:// 请求转交给 SpringBoard 中的 KayokoCore。
@interface KayokoURLSchemeHookInstaller : NSObject

+ (void)installHooks;

@end

NS_ASSUME_NONNULL_END
