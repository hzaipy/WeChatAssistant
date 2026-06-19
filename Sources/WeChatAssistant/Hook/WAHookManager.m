//
//  WAHookManager.m
//  WeChatAssistant
//
//  核心 Hook 管理器
//  对微信 4.1.x (QT/C++ 架构) 采用混合策略：
//  - 优先使用 Method Swizzling（对有 OC Runtime 暴露的方法）
//  - 对纯 C++/QT 方法通过 class-dump 定位后 Swizzle
//

#import "WAHookManager.h"
#import "WARevokeHook.h"
#import "WAGroupMonitorHook.h"
#import "WAThemeHook.h"
#import "WAConfigManager.h"
#import "WALogger.h"
#import <objc/runtime.h>

@interface WAHookManager ()
@property (nonatomic, strong) NSMutableArray<NSString *> *installedHooks;
@end

@implementation WAHookManager

+ (instancetype)sharedManager {
    static WAHookManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAHookManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _installedHooks = [NSMutableArray array];
    }
    return self;
}

- (void)installAllHooks {
    WAConfigManager *config = [WAConfigManager sharedManager];

    // 1. 多开（必须最早执行，不能延迟！）
    WALogInfo(@"安装多开 Patch...");
    [WARevokeHook installMultiOpenImmediately];
    [self.installedHooks addObject:@"multiOpen"];
    WALogInfo(@"✅ 多开 Patch 已安装");

    // 2. 防撤回 Hook（包含 dyld 回调注册）
    if ([config isFeatureEnabled:@"revokeProtection"]) {
        WALogInfo(@"安装防撤回 Hook...");
        BOOL ok = [WARevokeHook install];
        if (ok) {
            [self.installedHooks addObject:@"revokeProtection"];
            WALogInfo(@"✅ 防撤回 Hook 已安装");
        } else {
            WALogWarn(@"⚠️ 防撤回 Hook 安装失败");
        }
    }

    // 3. 禁止更新
    if ([config isFeatureEnabled:@"antiUpdate"]) {
        WALogInfo(@"安装禁止更新...");
        [WARevokeHook installAntiUpdateIfNeeded];
        [self.installedHooks addObject:@"antiUpdate"];
        WALogInfo(@"✅ 禁止更新已安装");
    }

    // 2. 退群监控 Hook
    if ([config isFeatureEnabled:@"groupMonitor"]) {
        WALogInfo(@"安装退群监控 Hook...");
        BOOL ok = [WAGroupMonitorHook install];
        if (ok) {
            [self.installedHooks addObject:@"groupMonitor"];
            WALogInfo(@"✅ 退群监控 Hook 已安装");
        } else {
            WALogWarn(@"⚠️ 退群监控 Hook 安装失败");
        }
    }

    // 3. 主题 Hook
    if ([config isFeatureEnabled:@"themeManager"]) {
        WALogInfo(@"安装主题 Hook...");
        BOOL ok = [WAThemeHook install];
        if (ok) {
            [self.installedHooks addObject:@"themeManager"];
            WALogInfo(@"✅ 主题 Hook 已安装");
        } else {
            WALogWarn(@"⚠️ 主题 Hook 安装失败");
        }
    }

    WALogInfo(@"Hook 安装完成: %@", self.installedHooks);
}

- (void)uninstallAllHooks {
    // Method Swizzling 的 Hook 在进程生命周期内无法安全卸载
    // 但可以禁用功能逻辑
    WALogInfo(@"Hook 卸载（功能禁用）");
    [WARevokeHook uninstall];
    [WAGroupMonitorHook uninstall];
    [WAThemeHook uninstall];
    [self.installedHooks removeAllObjects];
}

- (BOOL)hookClass:(NSString *)className
         selector:(SEL)originalSelector
     replacement:(IMP)replacementIMP
     originalIMP:(IMP *)originalIMP {

    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        WALogWarn(@"类 %@ 未找到，无法 Hook", className);
        return NO;
    }

    Method originalMethod = class_getInstanceMethod(targetClass, originalSelector);
    if (!originalMethod) {
        // 尝试类方法
        originalMethod = class_getClassMethod(targetClass, originalSelector);
        if (!originalMethod) {
            WALogWarn(@"方法 %@ 在类 %@ 中未找到", NSStringFromSelector(originalSelector), className);
            return NO;
        }
        // 类方法的 Hook
        if (originalIMP) *originalIMP = method_getImplementation(originalMethod);
        method_setImplementation(originalMethod, replacementIMP);
        WALogInfo(@"已 Hook 类方法 +[%@ %@]", className, NSStringFromSelector(originalSelector));
        return YES;
    }

    // 实例方法的 Hook
    if (originalIMP) *originalIMP = method_getImplementation(originalMethod);
    method_setImplementation(originalMethod, replacementIMP);
    WALogInfo(@"已 Hook 实例方法 -[%@ %@]", className, NSStringFromSelector(originalSelector));
    return YES;
}

@end
