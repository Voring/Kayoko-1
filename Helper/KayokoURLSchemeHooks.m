//
//  KayokoURLSchemeHooks.m
//  Kayoko
//
//  应用内 / 键盘扩展里的 kayoko:// 转发已不再需要：SpringBoard 自己会接住所有
//  kayoko:// 与 Prefs:root=Kayoko_*（见 Core/URLScheme/KayokoURLDispatchHooks.m）。
//  保留同名空 installer，不挂任何 UIApplication / LSApplicationWorkspace 钩子。
//

#import "KayokoURLSchemeHooks.h"

@implementation KayokoURLSchemeHookInstaller

+ (void)installHooks {
    // no-op
}

@end
