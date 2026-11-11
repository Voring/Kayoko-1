//
//  KayokoURLSchemeServer.m
//  Kayoko
//
//  跨进程 request.plist / Darwin 通知通道已不再使用：URL 在 SpringBoard 的
//  URL 分发处就地处理（见 KayokoURLDispatchHooks.m）。
//  保留同名的空实现，仅为满足 KayokoCore.m 里遗留的一行 start 调用，不注册任何
//  监听、不轮询、不碰文件。
//

#import "KayokoURLSchemeServer.h"

@implementation KayokoURLSchemeServer

+ (instancetype)sharedServer {
    static KayokoURLSchemeServer *server;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      server = [[self alloc] init];
    });
    return server;
}

- (BOOL)start {
    return YES;
}

- (void)stop {
}

@end
