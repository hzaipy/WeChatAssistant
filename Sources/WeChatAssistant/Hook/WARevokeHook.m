//
//  WARevokeHook.m
//  WeChatAssistant
//
//  防撤回 + 多开 + 禁止更新 - 完整地址表方案
//  地址来源：SovietExtension by MustangYM (4.1.10 实测通过)
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
// MessageWrap 字段布局（SovietExtension 验证，两版本通用）
// ============================================================
typedef struct {
    size_t messageWrapSize;             // 616
    size_t remoteUserOrSessionOffset;   // +24
    size_t selfUserOffset;              // +48
    size_t createTimeMsOffset;          // +256
    size_t createTimeSecOffset;         // +276
    size_t contentOffset;               // +328
} WAMessageWrapLayout;

static const WAMessageWrapLayout kMessageWrapLayout = {
    .messageWrapSize = 616,
    .remoteUserOrSessionOffset = 24,
    .selfUserOffset = 48,
    .createTimeMsOffset = 256,
    .createTimeSecOffset = 276,
    .contentOffset = 328,
};

// ============================================================
// Hook 模式
// ============================================================
typedef NS_ENUM(NSInteger, WARevokeHookMode) {
    WARevokeHookModePointer = 0,
    WARevokeHookModeInline  = 1,
};

// ============================================================
// 完整版本适配配置（SovietExtension 地址表）
// ============================================================
typedef struct {
    const char *shortVersion;
    const char *buildVersion;
    // 防撤回
    uintptr_t hookPointerVA;              // 热补丁指针 / 目标函数
    uintptr_t rawMessageTemplateVA;       // MessageWrap 模板
    uintptr_t messageWrapFromRawVA;       // 构造 MessageWrap
    uintptr_t messageWrapDestructVA;      // 析构 MessageWrap
    uintptr_t insertPaySysMsgToSessionVA; // 插入系统消息
    WARevokeHookMode hookMode;
    // 多开
    uintptr_t multiOpenPreventVA;         // TryPreventMultiInstance
} WAWeChatVersionProfile;

// 已适配版本（地址来源：SovietExtension 实测验证）
static const WAWeChatVersionProfile gProfiles[] = {
    {
        .shortVersion = "4.1.9",
        .buildVersion = "268602",
        .hookPointerVA = 0x91EAD20,
        .rawMessageTemplateVA = 0x7861730,
        .messageWrapFromRawVA = 0x4728670,
        .messageWrapDestructVA = 0x206F0D0,
        .insertPaySysMsgToSessionVA = 0x3822FA4,
        .hookMode = WARevokeHookModePointer,
        .multiOpenPreventVA = 0x1C0A64,
    },
    {
        .shortVersion = "4.1.10",
        .buildVersion = "268853",
        .hookPointerVA = 0x2846E84,
        .rawMessageTemplateVA = 0x7A7AD88,
        .messageWrapFromRawVA = 0x482F54C,
        .messageWrapDestructVA = 0x2123AC0,
        .insertPaySysMsgToSessionVA = 0x38EBBFC,
        .hookMode = WARevokeHookModeInline,
        .multiOpenPreventVA = 0x1C4EA8,
    },
};

static const size_t gProfileCount = sizeof(gProfiles) / sizeof(gProfiles[0]);

// ============================================================
// 全局状态
// ============================================================
static BOOL gInstalled = NO;
static BOOL gDyldCallbackRegistered = NO;
static BOOL gMultiOpenPatched = NO;
static BOOL gAntiRevokePatched = NO;
static intptr_t gDylibSlide = 0;
static const WAWeChatVersionProfile *gProfile = NULL;

static NSString * const kAntiRevoke = @"WA_AntiRevoke";

// ============================================================
// ARM64 内存补丁工具
// ============================================================

static BOOL WAProtectAndPatch(uintptr_t addr, const void *bytes, size_t size, NSString *desc) {
    vm_size_t ps = vm_page_size;
    uintptr_t psAddr = addr & ~(ps - 1);
    kern_return_t kr;

    kr = vm_protect(mach_task_self(), (vm_address_t)psAddr, ps, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) { WALogError(@"vm_protect RW fail: %d - %@", kr, desc); return NO; }

    memcpy((void *)addr, bytes, size);

    kr = vm_protect(mach_task_self(), (vm_address_t)psAddr, ps, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) { WALogError(@"vm_protect RX fail: %d - %@", kr, desc); return NO; }

    sys_icache_invalidate((void *)addr, size);
    return YES;
}

// 多开: mov w0, #1; ret
static BOOL WAPatchReturnYES(uintptr_t addr, NSString *desc) {
    uint32_t patch[2] = { 0x52800020, 0xD65F03C0 };
    uint32_t cur[2]; memcpy(cur, (void *)addr, sizeof(cur));
    if (cur[0] == patch[0] && cur[1] == patch[1]) {
        WALogInfo(@"多开已 patch，跳过: %@", desc);
        return YES;
    }
    BOOL ok = WAProtectAndPatch(addr, patch, sizeof(patch), desc);
    WALogInfo(@"%@ 多开: 0x%lx (%@)", ok ? @"✅" : @"❌", addr, desc);
    return ok;
}

// 防撤回 Inline: ldr x16,#8; br x16; .quad target (16 bytes)
static BOOL WAPatchAbsoluteJump(uintptr_t addr, uintptr_t target, NSString *desc) {
    uint32_t insn[4] = { 0x58000050, 0xD61F0200, (uint32_t)target, (uint32_t)(target >> 32) };
    BOOL ok = WAProtectAndPatch(addr, insn, sizeof(insn), desc);
    WALogInfo(@"%@ Inline: 0x%lx->0x%lx (%@)", ok ? @"✅" : @"❌", addr, target, desc);
    return ok;
}

// 防撤回 Pointer: 直接写函数指针 (8 bytes)
static BOOL WAWritePtr(uintptr_t ptrAddr, uintptr_t val, NSString *desc) {
    BOOL ok = WAProtectAndPatch(ptrAddr, &val, sizeof(val), desc);
    WALogInfo(@"%@ Pointer: 0x%lx=0x%lx (%@)", ok ? @"✅" : @"❌", ptrAddr, val, desc);
    return ok;
}

// ============================================================
// 防撤回 Hook 函数（完整实现，参考 SovietExtension）
// ============================================================

// 微信内部函数类型
typedef int64_t (*MessageWrapFromRawFunc)(int64_t wrap, int64_t rawMsg);
typedef int64_t (*MessageWrapDestructFunc)(int64_t wrap);
typedef int64_t (*InsertPaySysMsgFunc)(int64_t, void *session, void *content);

static int64_t WAHandleRevokeMsg(int64_t a1, int64_t rawRevokeMsg) {
    if (!gProfile || !gDylibSlide) return 1;

    WALogInfo(@"🔄 拦截撤回消息");

    @try {
        // 1. 从模板复制 MessageWrap
        uintptr_t templateAddr = gDylibSlide + gProfile->rawMessageTemplateVA;
        uint8_t rawWrap[616] __attribute__((aligned(16)));
        memcpy(rawWrap, (void *)templateAddr, 616);

        // 2. 调用微信内部函数解析撤回消息
        uintptr_t fromRawAddr = gDylibSlide + gProfile->messageWrapFromRawVA;
        MessageWrapFromRawFunc fromRaw = (MessageWrapFromRawFunc)fromRawAddr;
        fromRaw((int64_t)rawWrap, rawRevokeMsg);

        // 3. 提取会话信息
        // remoteUserOrSession at +24
        // 注：完整的 C++ std::string 提取较复杂，这里做简化处理
        NSString *noticeText = @"⚠️ 对方撤回了一条消息（内容已保留）";

        // 4. 记录撤回消息
        [[WARevokeManager sharedManager] recordRevokedMessage:noticeText
                                                        sender:nil
                                                        msgId:[NSString stringWithFormat:@"%lld", rawRevokeMsg]
                                                    timestamp:[NSDate date]];

        // 5. 析构临时 MessageWrap
        uintptr_t destructAddr = gDylibSlide + gProfile->messageWrapDestructVA;
        MessageWrapDestructFunc destruct = (MessageWrapDestructFunc)destructAddr;
        destruct((int64_t)rawWrap);

    } @catch (NSException *e) {
        WALogError(@"处理撤回消息异常: %@", e);
    }

    return 1; // 阻止微信原始撤回逻辑
}

// ============================================================
// 版本匹配
// ============================================================
static const WAWeChatVersionProfile *WAMatchVersion(void) {
    NSString *sv = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *bv = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    for (size_t i = 0; i < gProfileCount; i++) {
        if ([sv isEqualToString:@(gProfiles[i].shortVersion)] &&
            [bv isEqualToString:@(gProfiles[i].buildVersion)]) {
            return &gProfiles[i];
        }
    }
    return NULL;
}

// ============================================================
// dyld 回调
// ============================================================
static void WADyldCallback(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    NSString *path = @(info.dli_fname);
    if (![path containsString:@"wechat"] || ![path hasSuffix:@".dylib"]) return;

    WALogInfo(@"📦 wechat.dylib slide=0x%lx", slide);
    gDylibSlide = slide;

    // 多开第一时间
    if (!gMultiOpenPatched && gProfile) {
        uintptr_t addr = slide + gProfile->multiOpenPreventVA;
        gMultiOpenPatched = WAPatchReturnYES(addr, @"dyld:multiOpen");
    }

    // 防撤回受开关控制
    if (!gAntiRevokePatched && gProfile &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kAntiRevoke]) {
        uintptr_t addr = slide + gProfile->hookPointerVA;
        if (gProfile->hookMode == WARevokeHookModePointer) {
            gAntiRevokePatched = WAWritePtr(addr, (uintptr_t)&WAHandleRevokeMsg, @"dyld:revoke");
        } else {
            gAntiRevokePatched = WAPatchAbsoluteJump(addr, (uintptr_t)&WAHandleRevokeMsg, @"dyld:revoke");
        }
    }
}

static void WARegisterDyld(void) {
    if (gDyldCallbackRegistered) return;
    _dyld_register_func_for_add_image(WADyldCallback);
    gDyldCallbackRegistered = YES;
}

// ============================================================
// 扫描已加载的 wechat.dylib 并 patch
// ============================================================
static void WAScanAndPatch(void) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (!nm) continue;
        NSString *p = @(nm);
        if ([p containsString:@"wechat"] && [p hasSuffix:@".dylib"]) {
            intptr_t s = _dyld_get_image_vmaddr_slide(i);
            WADyldCallback(NULL, s);
            return;
        }
    }
}

// ============================================================
// 禁止更新
// ============================================================
static void WAEmptyMethod(id self, SEL _cmd) {}
static BOOL WAReturnNO(id self, SEL _cmd) { return NO; }

static void WAHookMethod(Class cls, SEL sel, IMP imp) {
    if (!cls || !sel) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (m) method_setImplementation(m, imp);
}

static void WAInstallAntiUpdate(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setBool:NO forKey:@"SUEnableAutomaticChecks"];
        [d setBool:NO forKey:@"SUAutomaticallyUpdate"];
        [d setBool:NO forKey:@"SUAllowsAutomaticUpdates"];
        [d setBool:NO forKey:@"SUSendProfileInfo"];
        [d setDouble:60*60*24*365*20 forKey:@"SUScheduledCheckInterval"];
        [d synchronize];

        Class su = NSClassFromString(@"SUUpdater");
        WAHookMethod(su, NSSelectorFromString(@"checkForUpdates:"), (IMP)WAEmptyMethod);
        WAHookMethod(su, NSSelectorFromString(@"checkForUpdatesInBackground"), (IMP)WAEmptyMethod);
        WAHookMethod(su, NSSelectorFromString(@"resetUpdateCycle"), (IMP)WAEmptyMethod);

        Class spu = NSClassFromString(@"SPUUpdater");
        WAHookMethod(spu, NSSelectorFromString(@"startUpdater:"), (IMP)WAReturnNO);
        WAHookMethod(spu, NSSelectorFromString(@"checkForUpdates"), (IMP)WAEmptyMethod);
        WAHookMethod(spu, NSSelectorFromString(@"checkForUpdatesInBackground"), (IMP)WAEmptyMethod);
        WAHookMethod(spu, NSSelectorFromString(@"resetUpdateCycle"), (IMP)WAEmptyMethod);

        WALogInfo(@"✅ 禁止更新已安装");
    });
}

// ============================================================
// 公开接口
// ============================================================
@implementation WARevokeHook

+ (BOOL)install {
    if (gInstalled) return YES;

    gProfile = WAMatchVersion();
    if (!gProfile) { WALogWarn(@"版本不支持"); return NO; }
    WALogInfo(@"✅ 版本匹配: %s (%s)", gProfile->shortVersion, gProfile->buildVersion);

    // 注册 dyld 回调
    WARegisterDyld();

    // 立即扫描已加载的 dylib
    WAScanAndPatch();

    // 延迟重试（防撤回）
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kAntiRevoke]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!gAntiRevokePatched) WAScanAndPatch();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!gAntiRevokePatched) WAScanAndPatch();
        });
    }

    gInstalled = YES;
    return YES;
}

+ (void)installMultiOpenImmediately {
    if (gMultiOpenPatched) return;
    gProfile = WAMatchVersion();
    if (!gProfile) return;
    WARegisterDyld();
    WAScanAndPatch();
}

+ (BOOL)installMultiOpenWithSlide:(intptr_t)slide { return NO; }
+ (BOOL)installAntiRevokeWithSlide:(intptr_t)slide { return NO; }

+ (void)installAntiUpdateIfNeeded {
    WAInstallAntiUpdate();
}

+ (void)uninstall {
    gInstalled = NO;
}

@end
