//
//  WARevokeHook.m
//  WeChatAssistant
//
//  防撤回实现 - 借鉴 SovietExtension 的 dyld 回调 + ARM64 内存补丁方案
//
//  核心思路（来自 SovietExtension/MustangYM）：
//  1. 通过 _dyld_register_func_for_add_image 监听 wechat.dylib 加载
//  2. 在 dyld 回调中获取 ASLR slide，计算运行时地址
//  3. 使用 vm_protect 修改内存页权限
//  4. 在目标函数入口写入 ARM64 绝对跳转指令
//  5. sys_icache_invalidate 刷新指令缓存
//
//  支持版本（仅 M 芯片 arm64）：
//  - 微信 4.1.9.58 (268602) - Pointer Hook 模式
//  - 微信 4.1.10.53 (268853) - Inline Hook 模式
//

#import "WARevokeHook.h"
#import "WARevokeManager.h"
#import "WALogger.h"
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <libkern/OSCacheControl.h>

// ============================================================
// 版本适配配置
// ============================================================
typedef NS_ENUM(NSInteger, WARevokeHookMode) {
    WARevokeHookModePointer = 0,  // 写入函数指针
    WARevokeHookModeInline  = 1,  // 直接 patch 函数入口
};

typedef struct {
    const char *shortVersion;       // CFBundleShortVersionString
    const char *buildVersion;       // CFBundleVersion
    uintptr_t hookPointerVA;        // 热补丁函数指针地址 / 目标函数地址
    WARevokeHookMode hookMode;      // Hook 方式
} WAWeChatVersionProfile;

// 已适配的微信版本（仅 arm64 M 芯片）
static const WAWeChatVersionProfile gSupportedVersions[] = {
    // 4.1.9.58 - Pointer 模式
    {
        .shortVersion = "4.1.9",
        .buildVersion = "268602",
        .hookPointerVA = 0x91EAD20,
        .hookMode = WARevokeHookModePointer,
    },
    // 4.1.10.53 - Inline 模式
    {
        .shortVersion = "4.1.10",
        .buildVersion = "268853",
        .hookPointerVA = 0x2846E84,
        .hookMode = WARevokeHookModeInline,
    },
};

static const size_t gSupportedVersionCount = sizeof(gSupportedVersions) / sizeof(gSupportedVersions[0]);

// ============================================================
// 全局状态
// ============================================================
static BOOL gInstalled = NO;
static BOOL gDyldCallbackRegistered = NO;
static intptr_t gWeChatDylibSlide = 0;
static const WAWeChatVersionProfile *gCurrentProfile = NULL;

// ============================================================
// 防撤回 Hook 函数（替换微信原始撤回处理）
// ============================================================
static int64_t WAHandleRevokeMsg(int64_t a1, int64_t rawRevokeMessage) {
    WALogInfo(@"🔄 拦截到撤回消息: rawMsg=0x%llx", rawRevokeMessage);

    // 记录撤回消息
    [[WARevokeManager sharedManager] recordRevokedMessage:@"[消息已被撤回]"
                                                    sender:nil
                                                    msgId:[NSString stringWithFormat:@"%lld", rawRevokeMessage]
                                                timestamp:[NSDate date]];

    // 返回 1 告诉微信系统消息已处理，阻止撤回
    return 1;
}

// ============================================================
// ARM64 内存补丁工具函数
// ============================================================

// 写入绝对跳转 (Inline Hook) - 16 字节
// ldr x16, #8  → 0x58000050
// br  x16       → 0xD61F0200
// .quad target
static BOOL WAPatchARM64AbsoluteJump(uintptr_t targetAddress, uintptr_t hookAddress, NSString *desc) {
    uint32_t instructions[4];
    instructions[0] = 0x58000050;  // ldr x16, #8
    instructions[1] = 0xD61F0200;  // br  x16
    instructions[2] = (uint32_t)(hookAddress & 0xFFFFFFFF);
    instructions[3] = (uint32_t)(hookAddress >> 32);

    kern_return_t kr;
    vm_size_t pageSize = vm_page_size;
    uintptr_t pageStart = targetAddress & ~(pageSize - 1);
    size_t patchSize = sizeof(instructions);

    // 修改内存页权限为可读写
    kr = vm_protect(mach_task_self(), (vm_address_t)pageStart, pageSize, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        WALogError(@"vm_protect(RW) 失败: %d - %@", kr, desc);
        return NO;
    }

    // 写入跳转指令
    memcpy((void *)targetAddress, instructions, patchSize);

    // 恢复内存页权限为可读可执行
    kr = vm_protect(mach_task_self(), (vm_address_t)pageStart, pageSize, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        WALogError(@"vm_protect(RX) 失败: %d - %@", kr, desc);
        return NO;
    }

    // 刷新指令缓存
    sys_icache_invalidate((void *)targetAddress, patchSize);

    WALogInfo(@"✅ Inline Hook 成功: 0x%lx -> 0x%lx (%@)", targetAddress, hookAddress, desc);
    return YES;
}

// 写入函数指针 (Pointer Hook) - 8 字节
static BOOL WAWritePointer(uintptr_t pointerAddress, uintptr_t hookAddress, NSString *desc) {
    kern_return_t kr;
    vm_size_t pageSize = vm_page_size;
    uintptr_t pageStart = pointerAddress & ~(pageSize - 1);

    kr = vm_protect(mach_task_self(), (vm_address_t)pageStart, pageSize, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        WALogError(@"vm_protect(RW) 失败: %d - %@", kr, desc);
        return NO;
    }

    *(uintptr_t *)pointerAddress = hookAddress;

    kr = vm_protect(mach_task_self(), (vm_address_t)pageStart, pageSize, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        WALogError(@"vm_protect(RX) 失败: %d - %@", kr, desc);
        return NO;
    }

    WALogInfo(@"✅ Pointer Hook 成功: 0x%lx -> 0x%lx (%@)", pointerAddress, hookAddress, desc);
    return YES;
}

// ============================================================
// 版本检测与匹配
// ============================================================
+ (const WAWeChatVersionProfile *)matchCurrentVersion {
    NSString *shortVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

    WALogInfo(@"当前微信版本: %@ (%@)", shortVer, buildVer);

    for (size_t i = 0; i < gSupportedVersionCount; i++) {
        NSString *sv = [NSString stringWithUTF8String:gSupportedVersions[i].shortVersion];
        NSString *bv = [NSString stringWithUTF8String:gSupportedVersions[i].buildVersion];

        if ([sv isEqualToString:shortVer] && [bv isEqualToString:buildVer]) {
            WALogInfo(@"✅ 版本匹配: %@ (%@)", sv, bv);
            return &gSupportedVersions[i];
        }
    }

    WALogWarn(@"⚠️ 当前版本 %@ (%@) 不在支持列表中", shortVer, buildVer);
    return NULL;
}

// ============================================================
// 安装防撤回补丁（在 dyld 回调中调用）
// ============================================================
+ (BOOL)installPatchWithSlide:(intptr_t)slide {
    if (!gCurrentProfile) return NO;

    uintptr_t runtimeAddress = slide + gCurrentProfile->hookPointerVA;
    uintptr_t hookFuncAddress = (uintptr_t)&WAHandleRevokeMsg;
    BOOL ok = NO;

    switch (gCurrentProfile->hookMode) {
        case WARevokeHookModePointer:
            ok = WAWritePointer(runtimeAddress, hookFuncAddress,
                                [NSString stringWithFormat:@"revoke pointer @ 0x%lx", runtimeAddress]);
            break;
        case WARevokeHookModeInline:
            ok = WAPatchARM64AbsoluteJump(runtimeAddress, hookFuncAddress,
                                          [NSString stringWithFormat:@"revoke inline @ 0x%lx", runtimeAddress]);
            break;
    }

    return ok;
}

// ============================================================
// dyld 回调 - 监听 wechat.dylib 加载
// ============================================================
static void WADyldImageAdded(const struct mach_header *mh, intptr_t vmaddr_slide) {
    // 检查是否是 wechat.dylib
    Dl_info info;
    if (dladdr(mh, &info) && info.dli_fname) {
        NSString *path = [NSString stringWithUTF8String:info.dli_fname];
        if ([path containsString:@"wechat"] && [path hasSuffix:@".dylib"]) {
            WALogInfo(@"📦 检测到 wechat.dylib 加载: %@ slide=0x%lx", path, vmaddr_slide);
            gWeChatDylibSlide = vmaddr_slide;

            // 立即安装防撤回补丁
            [WARevokeHook installPatchWithSlide:vmaddr_slide];
        }
    }
}

+ (void)registerDyldCallback {
    if (gDyldCallbackRegistered) return;
    _dyld_register_func_for_add_image(WADyldImageAdded);
    gDyldCallbackRegistered = YES;
    WALogInfo(@"dyld 回调已注册");
}

// ============================================================
// 公开接口
// ============================================================
@implementation WARevokeHook

+ (BOOL)install {
    if (gInstalled) return YES;

    // 1. 匹配当前微信版本
    gCurrentProfile = [self matchCurrentVersion];
    if (!gCurrentProfile) {
        WALogWarn(@"当前微信版本不支持，防撤回功能不可用");
        return NO;
    }

    // 2. 注册 dyld 回调（当 wechat.dylib 加载时自动 patch）
    [self registerDyldCallback];

    // 3. 尝试立即安装（如果 wechat.dylib 已经加载）
    // 遍历已加载的镜像
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "wechat") && strstr(name, ".dylib")) {
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            WALogInfo(@"wechat.dylib 已加载，立即安装补丁 slide=0x%lx", slide);
            [self installPatchWithSlide:slide];
            break;
        }
    }

    gInstalled = YES;
    return YES;
}

+ (void)uninstall {
    // 内存补丁在进程生命周期内无法安全还原
    // 只能禁用功能逻辑
    gInstalled = NO;
    WALogInfo(@"防撤回 Hook 已卸载（功能禁用）");
}

@end
