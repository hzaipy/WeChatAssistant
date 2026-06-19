//
//  main.m
//  WeChatAssistant - 动态库入口
//
//  macOS 微信助手 - 主注入动态库
//  仅支持 Apple Silicon (arm64) + 微信 4.1.x
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "WAHookManager.h"
#import "WAConfigManager.h"
#import "WARevokeManager.h"
#import "WAGroupMonitorManager.h"
#import "WAThemeManager.h"
#import "WALogger.h"

// ============================================================
// 入口控制器
// ============================================================
@interface WAEntryController : NSObject
@end

@implementation WAEntryController

// ============================================================
// 动态库加载时的初始化
// ============================================================
__attribute__((constructor))
static void WeChatAssistantInit(void) {
    @autoreleasepool {
        WALogInfo(@"========================================");
        WALogInfo(@"WeChatAssistant v1.0.0 - Apple Silicon");
        WALogInfo(@"目标: 微信 4.1.x (QT/C++)");
        WALogInfo(@"========================================");

        WAConfigManager *config = [WAConfigManager sharedManager];
        [config loadConfig];

        WARevokeManager *revokeManager = [WARevokeManager sharedManager];
        [revokeManager setupDatabase];

        WAGroupMonitorManager *groupMonitor = [WAGroupMonitorManager sharedManager];
        [groupMonitor startMonitoring];

        WAThemeManager *themeManager = [WAThemeManager sharedManager];
        [themeManager loadCurrentTheme];

        WAHookManager *hookManager = [WAHookManager sharedManager];
        [hookManager installAllHooks];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [WAEntryController setupMenuWithRetry:0];
        });

        WALogInfo(@"WeChatAssistant 初始化完成 ✅");
    }
}

// ============================================================
// 菜单安装
// ============================================================
+ (void)setupMenuWithRetry:(int)retryCount {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (!mainMenu && retryCount < 10) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self setupMenuWithRetry:retryCount + 1];
        });
        return;
    }
    if (!mainMenu) return;
    if ([mainMenu itemWithTitle:@"微信助手"] != nil) return;

    NSMenuItem *assistantItem = [[NSMenuItem alloc] initWithTitle:@"微信助手" action:nil keyEquivalent:@""];
    NSMenu *assistantMenu = [[NSMenu alloc] initWithTitle:@"微信助手"];

    // 偏好设置
    NSMenuItem *prefItem = [[NSMenuItem alloc] initWithTitle:@"偏好设置..."
                                                      action:@selector(wa_openPreferences)
                                               keyEquivalent:@","];
    prefItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    prefItem.target = self;
    [assistantMenu addItem:prefItem];
    [assistantMenu addItem:[NSMenuItem separatorItem]];

    // 功能开关
    NSMenuItem *multiOpenItem = [[NSMenuItem alloc] initWithTitle:@"✅ 多开"
                                                           action:@selector(wa_toggleMultiOpen) keyEquivalent:@""];
    multiOpenItem.target = self;
    [assistantMenu addItem:multiOpenItem];

    NSMenuItem *antiUpdateItem = [[NSMenuItem alloc] initWithTitle:@"✅ 禁止更新"
                                                            action:@selector(wa_toggleAntiUpdate) keyEquivalent:@""];
    antiUpdateItem.target = self;
    [assistantMenu addItem:antiUpdateItem];

    NSMenuItem *revokeItem = [[NSMenuItem alloc] initWithTitle:@"✅ 消息防撤回"
                                                        action:@selector(wa_toggleRevoke) keyEquivalent:@""];
    revokeItem.target = self;
    [assistantMenu addItem:revokeItem];

    NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:@"✅ 退群监控"
                                                       action:@selector(wa_toggleGroupMonitor) keyEquivalent:@""];
    groupItem.target = self;
    [assistantMenu addItem:groupItem];

    NSMenuItem *themeItem = [[NSMenuItem alloc] initWithTitle:@"✅ 皮肤模式"
                                                       action:@selector(wa_toggleTheme) keyEquivalent:@""];
    themeItem.target = self;
    [assistantMenu addItem:themeItem];

    [assistantMenu addItem:[NSMenuItem separatorItem]];

    // 皮肤子菜单
    NSMenuItem *themeSubItem = [[NSMenuItem alloc] initWithTitle:@"皮肤模式" action:nil keyEquivalent:@""];
    NSMenu *themeSubMenu = [[NSMenu alloc] initWithTitle:@"皮肤模式"];
    for (NSString *name in [[WAThemeManager sharedManager] availableThemeNames]) {
        NSMenuItem *tItem = [[NSMenuItem alloc] initWithTitle:name
                                                       action:@selector(wa_selectTheme:) keyEquivalent:@""];
        tItem.target = self;
        [themeSubMenu addItem:tItem];
    }
    themeSubItem.submenu = themeSubMenu;
    [assistantMenu addItem:themeSubItem];

    // 撤回历史
    NSMenuItem *historyItem = [[NSMenuItem alloc] initWithTitle:@"撤回消息历史"
                                                         action:@selector(wa_openRevokeHistory) keyEquivalent:@""];
    historyItem.target = self;
    [assistantMenu addItem:historyItem];

    [assistantMenu addItem:[NSMenuItem separatorItem]];

    // 关于
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"关于微信助手"
                                                       action:@selector(wa_showAbout) keyEquivalent:@""];
    aboutItem.target = self;
    [assistantMenu addItem:aboutItem];

    assistantItem.submenu = assistantMenu;
    [mainMenu addItem:assistantItem];
    WALogInfo(@"菜单已安装");
}

// ============================================================
// 菜单动作
// ============================================================
+ (void)wa_openPreferences {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WAOpenPreferences" object:nil];
}

+ (void)wa_toggleMultiOpen {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"multiOpen"];
    [self showRestartAlert:@"多开" enabled:enabled];
}

+ (void)wa_toggleAntiUpdate {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"antiUpdate"];
    [self showRestartAlert:@"禁止更新" enabled:enabled];
}

+ (void)wa_toggleRevoke {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"revokeProtection"];
    [self showRestartAlert:@"消息防撤回" enabled:enabled];
}

+ (void)wa_toggleGroupMonitor {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"groupMonitor"];
    [self showRestartAlert:@"退群监控" enabled:enabled];
}

+ (void)wa_toggleTheme {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"themeManager"];
    [self showRestartAlert:@"皮肤模式" enabled:enabled];
}

+ (void)wa_selectTheme:(NSMenuItem *)sender {
    [[WAThemeManager sharedManager] switchToThemeNamed:sender.title];
}

+ (void)wa_openRevokeHistory {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WAOpenRevokeHistory" object:nil];
}

+ (void)wa_showAbout {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"微信助手 WeChatAssistant";
    alert.informativeText = @"版本 1.0.0\n\nmacOS 微信增强助手\n• 多开\n• 禁止更新\n• 消息防撤回\n• 退群监控\n• 皮肤模式（迷离/黑夜/上帝/少女）\n\n仅支持 Apple Silicon (M1/M2/M3/M4)\n微信 4.1.x 系列\n\n借鉴:\n• SovietExtension (4.x 防撤回+多开)\n• WeChatExtension-ForMac (皮肤方案)";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"确定"];
    [alert runModal];
}

+ (void)showRestartAlert:(NSString *)featureName enabled:(BOOL)enabled {
    if (!enabled) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"%@ 已开启", featureName];
    alert.informativeText = @"重启微信后生效";
    [alert addButtonWithTitle:@"稍后重启"];
    [alert addButtonWithTitle:@"立即重启"];
    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertSecondButtonReturn) {
        system("killall WeChat && open /Applications/WeChat.app");
    }
}

@end
