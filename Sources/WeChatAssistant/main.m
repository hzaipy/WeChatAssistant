//
//  main.m
//  WeChatAssistant - 动态库入口
//
//  macOS 微信助手 - 主注入动态库
//  通过 insert_dylib 注入到 WeChat.app 中运行
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
// 菜单回调声明
// ============================================================
static void openPreferences(void);
static void toggleRevokeProtection(void);
static void toggleGroupMonitor(void);
static void toggleTheme(void);
static void selectTheme(NSMenuItem *sender);
static void openRevokeHistory(void);
static void showAbout(void);

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

        // 1. 加载配置
        WAConfigManager *config = [WAConfigManager sharedManager];
        [config loadConfig];
        WALogInfo(@"配置加载完成");

        // 2. 初始化各功能管理器
        WARevokeManager *revokeManager = [WARevokeManager sharedManager];
        [revokeManager setupDatabase];

        WAGroupMonitorManager *groupMonitor = [WAGroupMonitorManager sharedManager];
        [groupMonitor startMonitoring];

        WAThemeManager *themeManager = [WAThemeManager sharedManager];
        [themeManager loadCurrentTheme];

        // 3. 安装所有 Hook
        WAHookManager *hookManager = [WAHookManager sharedManager];
        [hookManager installAllHooks];

        // 4. 延迟设置偏好菜单（等微信主窗口就绪）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self setupMenuWithRetry:0];
        });

        WALogInfo(@"WeChatAssistant 初始化完成 ✅");
    }
}

// ============================================================
// 菜单安装（带重试）
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
    if (!mainMenu) {
        WALogError(@"无法获取主菜单，菜单安装失败");
        return;
    }

    // 检查是否已安装
    if ([mainMenu itemWithTitle:@"微信助手"] != nil) {
        return;
    }

    NSMenuItem *assistantItem = [[NSMenuItem alloc] initWithTitle:@"微信助手"
                                                           action:nil
                                                    keyEquivalent:@""];
    NSMenu *assistantMenu = [[NSMenu alloc] initWithTitle:@"微信助手"];

    // --- 偏好设置 ---
    NSMenuItem *prefItem = [[NSMenuItem alloc] initWithTitle:@"偏好设置..."
                                                      action:@selector(wa_openPreferences)
                                               keyEquivalent:@","];
    prefItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    prefItem.target = [self class];
    [assistantMenu addItem:prefItem];

    [assistantMenu addItem:[NSMenuItem separatorItem]];

    // --- 功能开关 ---
    NSMenuItem *revokeItem = [[NSMenuItem alloc] initWithTitle:@"✅ 消息防撤回"
                                                        action:@selector(wa_toggleRevoke)
                                                 keyEquivalent:@""];
    revokeItem.target = [self class];
    [assistantMenu addItem:revokeItem];

    NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:@"✅ 退群监控"
                                                       action:@selector(wa_toggleGroupMonitor)
                                                keyEquivalent:@""];
    groupItem.target = [self class];
    [assistantMenu addItem:groupItem];

    NSMenuItem *themeItem = [[NSMenuItem alloc] initWithTitle:@"✅ 主题更换"
                                                       action:@selector(wa_toggleTheme)
                                                keyEquivalent:@""];
    themeItem.target = [self class];
    [assistantMenu addItem:themeItem];

    [assistantMenu addItem:[NSMenuItem separatorItem]];

    // --- 主题子菜单 ---
    NSMenuItem *themeSubItem = [[NSMenuItem alloc] initWithTitle:@"主题"
                                                          action:nil
                                                   keyEquivalent:@""];
    NSMenu *themeSubMenu = [[NSMenu alloc] initWithTitle:@"主题"];
    for (NSString *name in [[WAThemeManager sharedManager] availableThemes]) {
        NSMenuItem *tItem = [[NSMenuItem alloc] initWithTitle:name
                                                       action:@selector(wa_selectTheme:)
                                                keyEquivalent:@""];
        tItem.target = [self class];
        [themeSubMenu addItem:tItem];
    }
    themeSubItem.submenu = themeSubMenu;
    [assistantMenu addItem:themeSubItem];

    // --- 撤回历史 ---
    NSMenuItem *historyItem = [[NSMenuItem alloc] initWithTitle:@"撤回消息历史"
                                                         action:@selector(wa_openRevokeHistory)
                                                  keyEquivalent:@""];
    historyItem.target = [self class];
    [assistantMenu addItem:historyItem];

    [assistantMenu addItem:[NSMenuItem separatorItem]];

    // --- 关于 ---
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"关于微信助手"
                                                       action:@selector(wa_showAbout)
                                                keyEquivalent:@""];
    aboutItem.target = [self class];
    [assistantMenu addItem:aboutItem];

    assistantItem.submenu = assistantMenu;
    [mainMenu addItem:assistantItem];

    WALogInfo(@"菜单已安装到微信菜单栏");
}

// ============================================================
// 菜单动作
// ============================================================
+ (void)wa_openPreferences {
    WALogInfo(@"打开偏好设置");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WAOpenPreferences" object:nil];
}

+ (void)wa_toggleRevoke {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"revokeProtection"];
    WALogInfo(@"防撤回: %@", enabled ? @"开启" : @"关闭");
}

+ (void)wa_toggleGroupMonitor {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"groupMonitor"];
    WALogInfo(@"退群监控: %@", enabled ? @"开启" : @"关闭");
}

+ (void)wa_toggleTheme {
    BOOL enabled = [[WAConfigManager sharedManager] toggleFeature:@"themeManager"];
    WALogInfo(@"主题: %@", enabled ? @"开启" : @"关闭");
}

+ (void)wa_selectTheme:(NSMenuItem *)sender {
    [[WAThemeManager sharedManager] switchToTheme:sender.title];
}

+ (void)wa_openRevokeHistory {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WAOpenRevokeHistory" object:nil];
}

+ (void)wa_showAbout {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"微信助手 WeChatAssistant";
    alert.informativeText = @"版本 1.0.0\n\nmacOS 微信增强助手\n• 消息防撤回\n• 退群监控\n• 主题更换\n\n仅支持 Apple Silicon (M1/M2/M3/M4)\n微信 4.1.x 系列";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"确定"];
    [alert runModal];
}
