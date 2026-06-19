//
//  WARevokeHook.m
//  WeChatAssistant
//
//  核心功能实现 - 借鉴 SovietExtension 的 4.x 方案
//
//  包含三个功能（共用 dyld 回调 + 版本适配表）：
//  1. 防撤回 - Pointer/Inline Hook
//  2. 多开   - ARM64 patch TryPreventMultiInstance → return YES
//  3. 禁止更新 - Sparkle 禁用
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
#import <dlfcn.h>

// ============================================================
// 版本适配配置（扩展：加入多开和防更新地址）
// ============================================================
typedef NS_ENUM(NSInteger, WARevokeHookMode) {
    WARevokeHookModePointer = 0,
    WARevokeHookModeInline  = 1,
};

typedef struct {
    const char *shortVersion;
    const char *buildVersion;
    uintptr_t hookPointerVA;              // 防撤回: 热补丁指针/目标函数
    uintptr_t multiOpenPreventVA;         // 多开: TryPreventMultiInstance
    WARevokeHookMode hookMode;
} WAWeChatVersionProfile;

// 已适配的微信版本（仅 arm64 M 芯片）
static const WAWeChatVersionProfile gSupportedVersions[] = {
    {
        .shortVersion = "4.1.9",
        .buildVersion = "268602",
        .hookPointerVA = 0x91EAD20,
        .multiOpenPreventVA = 0x1C0A64,
        .hookMode = WARevokeHookModePointer,
    },
    {
        .shortVersion = "4.1.10",
        .buildVersion = "268853",
        .hookPointerVA = 0x2846E84,
        .multiOpenPreventVA = 0x1C4EA8,
        .hookMode = WARevokeHookModeInline,
    },
};

static const size_t gSupportedVersionCount = sizeof(gSupportedVersions) / sizeof(gSupportedVersions[0]);

// ============================================================
// 全局状态
// ============================================================
static BOOL gInstalled = NO;
static BOOL gDyldCallbackRegistered = NO;
static BOOL gMultiOpenPatched = NO;
static BOOL gAntiRevokePatched = NO;
static BOOL gAntiUpdateInstalled = NO;
static intptr_t gWeChatDylibSlide = 0;
static const WAWeChatVersionProfile *gCurrentProfile = NULL;

// NSUserDefaults 键
static NSString * const kAntiRevoke = @"WA_AntiRevoke";
static NSString * const kAntiUpdate = @"WA_AntiUpdate";
static NSString * const kIsFirstLoad = @"WA_IsFirstLoad";

// ============================================================
// 防撤回 Hook 函数
// ============================================================
static int64_t WAHandleRevokeMsg(int64_t a1, int64_t rawRevokeMessage) {
    WALogInfo(@"🔄 拦截到撤回消息: rawMsg=0x%llx", rawRevokeMessage);
    [[WARevokeManager sharedManager] recordRevokedMessage:@"[消息已被撤回]"
                                                    sender:nil
                                                    msgId:[NSString stringWithFormat:@"%lld", rawRevokeMessage]
                                                timestamp:[NSDate date]];
    return 1; // 返回 1 阻止撤回
}

// ============================================================
// ARM64 内存补丁工具函数
// ============================================================

static BOOL WAProtectAndPatch(uintptr_t address, const void *patchBytes, size_t patchSize, NSString *desc) {
    kern_return_t kr;
    vm_size_t pageSize = vm_page_size;
    uintptr_t pageStart = address & ~(pageSize - 1);

    kr = vm_protect(mach_task_self(), (vm_address_t)pageStart, pageSize, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        WALogError(@"vm_protect(RW|COPY) 失败: %d - %@", kr, desc);
        return NO;
    }

    memcpy((void *)address, patchBytes, patchSize);

    kr = vm_protect(mach_task_self(), (vm_address_t)pageStart, pageSize, FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        WALogError(@"vm_protect(RX) 失败: %d - %@", kr, desc);
        return NO;
    }

    sys_icache_invalidate((void *)address, patchSize);
    return YES;
}

// Inline Hook: ldr x16, #8; br x16; .quad target
static BOOL WAPatchARM64AbsoluteJump(uintptr_t targetAddress, uintptr_t hookAddress, NSString *desc) {
    uint32_t instructions[4];
    instructions[0] = 0x58000050;
    instructions[1] = 0xD61F0200;
    instructions[2] = (uint32_t)(hookAddress & 0xFFFFFFFF);
    instructions[3] = (uint32_t)(hookAddress >> 32);

    BOOL ok = WAProtectAndPatch(targetAddress, instructions, sizeof(instructions), desc);
    WALogInfo(@"%@ Inline Hook: 0x%lx -> 0x%lx (%@)",
              ok ? @"✅" : @"❌", targetAddress, hookAddress, desc);
    return ok;
}

// Pointer Hook: 直接写函数指针
static BOOL WAWritePointer(uintptr_t pointerAddress, uintptr_t hookAddress, NSString *desc) {
    BOOL ok = WAProtectAndPatch(pointerAddress, &hookAddress, sizeof(hookAddress), desc);
    WALogInfo(@"%@ Pointer Hook: 0x%lx -> 0x%lx (%@)",
              ok ? @"✅" : @"❌", pointerAddress, hookAddress, desc);
    return ok;
}

// 多开 Patch: mov w0, #1; ret → 强制返回 YES
static BOOL WAPatchARM64ReturnYES(uintptr_t address, NSString *desc) {
    uint32_t patch[2] = {
        0x52800020, // mov w0, #1
        0xD65F03C0  // ret
    };

    // 先检查是否已 patch
    uint32_t current[2] = {0};
    memcpy(current, (void *)address, sizeof(current));
    if (current[0] == patch[0] && current[1] == patch[1]) {
        WALogInfo(@"多开已 patch，跳过: %@", desc);
        return YES;
    }

    BOOL ok = WAProtectAndPatch(address, patch, sizeof(patch), desc);
    WALogInfo(@"%@ 多开 Patch: 0x%lx (%@)", ok ? @"✅" : @"❌", address, desc);
    return ok;
}

// ============================================================
// 版本检测
// ============================================================
@implementation WARevokeHook

+ (const void *)matchCurrentVersion {
    NSString *shortVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    WALogInfo(@"当前微信版本: %@ (%@)", shortVer, buildVer);

    for (size_t i = 0; i < gSupportedVersionCount; i++) {
        NSString *sv = [NSString stringWithUTF8String:gSupportedVersions[i].shortVersion];
        NSString *bv = [NSString stringWithUTF8String:gSupportedVersions[i].buildVersion];
        if ([sv isEqualToString:shortVer] && [bv isEqualToString:buildVersion]) {
            WALogInfo(@"✅ 版本匹配: %@ (%@)", sv, bv);
            return &gSupportedVersions[i];
        }
    }
    WALogWarn(@"⚠️ 当前版本不支持: %@ (%@)", shortVer, buildVer);
    return NULL;
}

// ============================================================
// 多开功能
// ============================================================
+ (BOOL)installMultiOpenWithSlide:(intptr_t)slide {
    if (gMultiOpenPatched) return YES;
    if (!gCurrentProfile) return NO;

    uintptr_t runtimeAddr = slide + gCurrentProfile->multiOpenPreventVA;
    BOOL ok = WAPatchARM64ReturnYES(runtimeAddr, @"TryPreventMultiInstance");

    if (ok) gMultiOpenPatched = YES;
    return ok;
}

+ (void)installMultiOpenImmediately {
    if (gMultiOpenPatched) return;

    gCurrentProfile = (const WAWeChatVersionProfile *)[self matchCurrentVersion];
    if (!gCurrentProfile) return;

    // 扫描已加载的 wechat.dylib
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "wechat") && strstr(name, ".dylib")) {
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            WALogInfo(@"多开: 发现 wechat.dylib slide=0x%lx", slide);
            [self installMultiOpenWithSlide:slide];
            return;
        }
    }
    WALogInfo(@"多开: wechat.dylib 尚未加载，等待 dyld 回调");
}

// ============================================================
// 防撤回功能
// ============================================================
+ (BOOL)installAntiRevokeWithSlide:(intptr_t)slide {
    if (gAntiRevokePatched) return YES;
    if (!gCurrentProfile) return NO;

    uintptr_t runtimeAddr = slide + gCurrentProfile->hookPointerVA;
    uintptr_t hookFuncAddr = (uintptr_t)&WAHandleRevokeMsg;
    BOOL ok = NO;

    switch (gCurrentProfile->hookMode) {
        case WARevokeHookModePointer:
            ok = WAWritePointer(runtimeAddr, hookFuncAddr,
                                [NSString stringWithFormat:@"revoke pointer @ 0x%lx", runtimeAddr]);
            break;
        case WARevokeHookModeInline:
            ok = WAPatchARM64AbsoluteJump(runtimeAddr, hookFuncAddr,
                                          [NSString stringWithFormat:@"revoke inline @ 0x%lx", runtimeAddr]);
            break;
    }

    if (ok) gAntiRevokePatched = YES;
    return ok;
}

// ============================================================
// 禁止更新功能（借鉴 SovietExtension AntiUpdate）
// ============================================================

// 禁用 Sparkle 默认配置
+ (void)disableSparkleDefaults {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if (![bundleID isEqualToString:@"com.tencent.xinWeChat"]) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:NO forKey:@"SUEnableAutomaticChecks"];
    [defaults setBool:NO forKey:@"SUAutomaticallyUpdate"];
    [defaults setBool:NO forKey:@"SUAllowsAutomaticUpdates"];
    [defaults setBool:NO forKey:@"SUSendProfileInfo"];
    [defaults setDouble:60 * 60 * 24 * 365 * 20 forKey:@"SUScheduledCheckInterval"];
    [defaults synchronize];
    WALogInfo(@"Sparkle 默认配置已禁用");
}

// 空操作替换
static void WAEmptyVoidMethod(id self, SEL _cmd) {
    WALogDebug(@"已阻止更新方法: %@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
}

static BOOL WAReturnNOMethod(id self, SEL _cmd) {
    WALogDebug(@"已阻止更新方法(BOOL): %@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
    return NO;
}

// Swizzle 实例方法为空操作
static void WASwizzleToNoop(Class cls, SEL sel, IMP newIMP, NSString *desc) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        WALogDebug(@"更新 Hook 方法未找到: %@", desc);
        return;
    }
    method_setImplementation(m, newIMP);
    WALogInfo(@"已 Hook 更新方法: %@", desc);
}

// Runtime Hook 阻止 Sparkle
+ (void)disableSparkleByRuntimeHook {
    WALogInfo(@"正在 Hook Sparkle 更新机制...");

    // Sparkle 1.x - SUUpdater
    Class SUUpdater = NSClassFromString(@"SUUpdater");
    if (SUUpdater) {
        WASwizzleToNoop(SUUpdater, NSSelectorFromString(@"checkForUpdates:"),
                        (IMP)WAEmptyVoidMethod, @"SUUpdater -checkForUpdates:");
        WASwizzleToNoop(SUUpdater, NSSelectorFromString(@"checkForUpdatesInBackground"),
                        (IMP)WAEmptyVoidMethod, @"SUUpdater -checkForUpdatesInBackground");
        WASwizzleToNoop(SUUpdater, NSSelectorFromString(@"resetUpdateCycle"),
                        (IMP)WAEmptyVoidMethod, @"SUUpdater -resetUpdateCycle");
    }

    // Sparkle 2.x - SPUUpdater
    Class SPUUpdater = NSClassFromString(@"SPUUpdater");
    if (SPUUpdater) {
        WASwizzleToNoop(SPUUpdater, NSSelectorFromString(@"startUpdater:"),
                        (IMP)WAReturnNOMethod, @"SPUUpdater -startUpdater:");
        WASwizzleToNoop(SPUUpdater, NSSelectorFromString(@"checkForUpdates"),
                        (IMP)WAEmptyVoidMethod, @"SPUUpdater -checkForUpdates");
        WASwizzleToNoop(SPUUpdater, NSSelectorFromString(@"checkForUpdatesInBackground"),
                        (IMP)WAEmptyVoidMethod, @"SPUUpdater -checkForUpdatesInBackground");
        WASwizzleToNoop(SPUUpdater, NSSelectorFromString(@"resetUpdateCycle"),
                        (IMP)WAEmptyVoidMethod, @"SPUUpdater -resetUpdateCycle");
    }

    gAntiUpdateInstalled = YES;
    WALogInfo(@"✅ Sparkle 更新机制已 Hook");
}

+ (void)installAntiUpdateIfNeeded {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // 首次加载自动开启防更新
        NSString *loadFlag = [[NSUserDefaults standardUserDefaults] objectForKey:kIsFirstLoad];
        if (loadFlag.length < 3) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAntiUpdate];
            [[NSUserDefaults standardUserDefaults] setObject:@"WEASSISTANT" forKey:kIsFirstLoad];
            [[NSUserDefaults standardUserDefaults] synchronize];
            WALogInfo(@"首次加载，自动开启禁止更新");
        }

        if ([[NSUserDefaults standardUserDefaults] boolForKey:kAntiUpdate]) {
            [self disableSparkleDefaults];
            [self disableSparkleByRuntimeHook];
        }
    });
}

// ============================================================
// dyld 回调
// ============================================================
static void WADyldImageAdded(const struct mach_header *mh, intptr_t vmaddr_slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;

    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    if (![path containsString:@"wechat"] || ![path hasSuffix:@".dylib"]) return;

    WALogInfo(@"📦 wechat.dylib 加载: %@ slide=0x%lx", [path lastPathComponent], vmaddr_slide);
    gWeChatDylibSlide = vmaddr_slide;

    // 多开必须第一时间 patch
    [WARevokeHook installMultiOpenWithSlide:vmaddr_slide];

    // 防撤回受用户开关控制
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kAntiRevoke]) {
        [WARevokeHook installAntiRevokeWithSlide:vmaddr_slide];
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
+ (BOOL)install {
    if (gInstalled) return YES;

    // 1. 版本匹配
    gCurrentProfile = (const WAWeChatVersionProfile *)[self matchCurrentVersion];
    if (!gCurrentProfile) {
        WALogWarn(@"当前微信版本不支持");
        return NO;
    }

    // 2. 注册 dyld 回调（多开 + 防撤回）
    [self registerDyldCallback];

    // 3. 多开立即安装（不能延迟！）
    [self installMultiOpenImmediately];

    // 4. 防撤回立即扫描 + 延迟重试
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kAntiRevoke]) {
        uint32_t count = _dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const char *name = _dyld_get_image_name(i);
            if (name && strstr(name, "wechat") && strstr(name, ".dylib")) {
                intptr_t slide = _dyld_get_image_vmaddr_slide(i);
                [self installAntiRevokeWithSlide:slide];
                break;
            }
        }
        // 延迟重试
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self installAntiRevokeIfLoaded]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self installAntiRevokeIfLoaded]; });
    }

    // 5. 禁止更新（延迟安装，等微信完全启动）
    [self installAntiUpdateIfNeeded];

    gInstalled = YES;
    return YES;
}

+ (void)installAntiRevokeIfLoaded {
    if (gAntiRevokePatched) return;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "wechat") && strstr(name, ".dylib")) {
            [self installAntiRevokeWithSlide:_dyld_get_image_vmaddr_slide(i)];
            break;
        }
    }
}

+ (void)uninstall {
    gInstalled = NO;
    WALogInfo(@"功能已禁用");
}

@end
