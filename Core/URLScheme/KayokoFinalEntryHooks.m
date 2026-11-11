//
//  KayokoFinalEntryHooks.m
//  Kayoko
//
//  已停用：直接在 FBSystemService -_reallyActivateApplication:... 上换 IMP 会导致
//  SpringBoard 反复注销（那根链条对参数/签名极其敏感）。保留空文件占位。
//

#import <Foundation/Foundation.h>
#import <CaptainHook/CaptainHook.h>

__attribute__((constructor)) static void KayokoFinalEntryHooksEntry(void) {
    @autoreleasepool {
        // no-op
    }
}
