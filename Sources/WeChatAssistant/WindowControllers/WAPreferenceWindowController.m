//
//  WAPreferenceWindowController.m
//  WeChatAssistant
//

#import "WAPreferenceWindowController.h"
#import "WAConfigManager.h"
#import "WALogger.h"

@interface WAPreferenceWindowController () <NSToolbarDelegate>
@property (nonatomic, strong) NSTabView *tabView;
@end

@implementation WAPreferenceWindowController

+ (instancetype)sharedController {
    static WAPreferenceWindowController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAPreferenceWindowController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 550, 400)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        [self setupWindow];
    }
    return self;
}

- (void)setupWindow {
    self.window.title = @"微信助手 - 偏好设置";
    [self.window center];

    // 工具栏
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"WAPreferenceToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.selectedItemIdentifier = @"general";
    self.window.toolbar = toolbar;

    // TabView
    self.tabView = [[NSTabView alloc] initWithFrame:self.window.contentView.bounds];
    self.tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // 通用 Tab
    NSTabViewItem *generalTab = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    generalTab.label = @"通用";
    generalTab.view = [self createGeneralTabView];
    [self.tabView addTabViewItem:generalTab];

    // 防撤回 Tab
    NSTabViewItem *revokeTab = [[NSTabViewItem alloc] initWithIdentifier:@"revoke"];
    revokeTab.label = @"防撤回";
    revokeTab.view = [self createRevokeTabView];
    [self.tabView addTabViewItem:revokeTab];

    // 退群监控 Tab
    NSTabViewItem *groupTab = [[NSTabViewItem alloc] initWithIdentifier:@"group"];
    groupTab.label = @"退群监控";
    groupTab.view = [self createGroupMonitorTabView];
    [self.tabView addTabViewItem:groupTab];

    // 主题 Tab
    NSTabViewItem *themeTab = [[NSTabViewItem alloc] initWithIdentifier:@"theme"];
    themeTab.label = @"主题";
    themeTab.view = [self createThemeTabView];
    [self.tabView addTabViewItem:themeTab];

    // 关于 Tab
    NSTabViewItem *aboutTab = [[NSTabViewItem alloc] initWithIdentifier:@"about"];
    aboutTab.label = @"关于";
    aboutTab.view = [self createAboutTabView];
    [self.tabView addTabViewItem:aboutTab];

    [self.window.contentView addSubview:self.tabView];
}

- (NSView *)createGeneralTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 400)];

    NSTextField *title = [self labelWithText:@"通用设置" fontSize:16 bold:YES frame:NSMakeRect(20, 350, 200, 24)];
    [view addSubview:title];

    // 功能开关
    NSArray *features = @[
        @{@"name": @"revokeProtection", @"label": @"消息防撤回", @"desc": @"拦截撤回消息，保留聊天记录"},
        @{@"name": @"groupMonitor", @"label": @"退群监控", @"desc": @"监控群成员退出并推送通知"},
        @{@"name": @"themeManager", @"label": @"主题更换", @"desc": @"自定义微信界面配色方案"},
    ];

    CGFloat y = 310;
    for (NSDictionary *feature in features) {
        NSButton *checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 300, 22)];
        [checkbox setButtonType:NSButtonTypeSwitch];
        checkbox.title = feature[@"label"];
        checkbox.state = [[WAConfigManager sharedManager] isFeatureEnabled:feature[@"name"]] ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.tag = [features indexOfObject:feature];
        checkbox.target = self;
        checkbox.action = @selector(featureToggleChanged:);
        [view addSubview:checkbox];

        NSTextField *desc = [self labelWithText:feature[@"desc"] fontSize:11 bold:NO frame:NSMakeRect(40, y - 18, 400, 16)];
        desc.textColor = [NSColor secondaryLabelColor];
        [view addSubview:desc];

        y -= 50;
    }

    // 开机自启
    NSButton *autoLaunchCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 140, 300, 22)];
    [autoLaunchCheckbox setButtonType:NSButtonTypeSwitch];
    autoLaunchCheckbox.title = @"登录时自动启动微信助手";
    autoLaunchCheckbox.state = [[[WAConfigManager sharedManager] objectForKey:@"autoLaunch"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:autoLaunchCheckbox];

    return view;
}

- (NSView *)createRevokeTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 400)];

    NSTextField *title = [self labelWithText:@"消息防撤回" fontSize:16 bold:YES frame:NSMakeRect(20, 350, 200, 24)];
    [view addSubview:title];

    NSTextField *desc = [self labelWithText:@"当对方撤回消息时，微信助手会保留消息内容并标记为「已撤回」。\n你可以随时在撤回消息历史中查看被撤回的消息。"
                                  fontSize:12 bold:NO
                                     frame:NSMakeRect(20, 290, 510, 50)];
    desc.textColor = [NSColor secondaryLabelColor];
    [view addSubview:desc];

    NSButton *viewHistoryBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 250, 150, 28)];
    viewHistoryBtn.title = @"查看撤回历史";
    viewHistoryBtn.bezelStyle = NSBezelStyleRounded;
    viewHistoryBtn.target = self;
    viewHistoryBtn.action = @selector(openRevokeHistory:);
    [view addSubview:viewHistoryBtn];

    NSButton *clearHistoryBtn = [[NSButton alloc] initWithFrame:NSMakeRect(180, 250, 150, 28)];
    clearHistoryBtn.title = @"清空记录";
    clearHistoryBtn.bezelStyle = NSBezelStyleRounded;
    clearHistoryBtn.target = self;
    clearHistoryBtn.action = @selector(clearRevokeHistory:);
    [view addSubview:clearHistoryBtn];

    return view;
}

- (NSView *)createGroupMonitorTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 400)];

    NSTextField *title = [self labelWithText:@"退群监控" fontSize:16 bold:YES frame:NSMakeRect(20, 350, 200, 24)];
    [view addSubview:title];

    NSTextField *desc = [self labelWithText:@"当群聊中有人退出或被移出群聊时，微信助手会记录事件并发送系统通知。\n通知内容包括：退群人、群名称、退出时间。"
                                  fontSize:12 bold:NO
                                     frame:NSMakeRect(20, 290, 510, 50)];
    desc.textColor = [NSColor secondaryLabelColor];
    [view addSubview:desc];

    NSButton *viewLogBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 250, 150, 28)];
    viewLogBtn.title = @"查看监控日志";
    viewLogBtn.bezelStyle = NSBezelStyleRounded;
    [view addSubview:viewLogBtn];

    return view;
}

- (NSView *)createThemeTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 400)];

    NSTextField *title = [self labelWithText:@"主题更换" fontSize:16 bold:YES frame:NSMakeRect(20, 350, 200, 24)];
    [view addSubview:title];

    NSTextField *desc = [self labelWithText:@"选择预设主题来改变微信的外观配色。\n主题变更将在重启微信后生效。"
                                  fontSize:12 bold:NO
                                     frame:NSMakeRect(20, 310, 510, 40)];
    desc.textColor = [NSColor secondaryLabelColor];
    [view addSubview:desc];

    // 主题预览
    NSArray *themeNames = @[@"Default", @"Dark", @"Minimal"];
    NSArray *themeColors = @[[NSColor colorWithRed:0.96 green:0.96 blue:0.96 alpha:1.0],
                              [NSColor colorWithRed:0.12 green:0.12 blue:0.12 alpha:1.0],
                              [NSColor colorWithRed:0.98 green:0.98 blue:0.98 alpha:1.0]];

    CGFloat x = 20;
    for (NSInteger i = 0; i < themeNames.count; i++) {
        NSView *preview = [[NSView alloc] initWithFrame:NSMakeRect(x, 200, 100, 80)];
        preview.wantsLayer = YES;
        preview.layer.backgroundColor = [themeColors[i] CGColor];
        preview.layer.cornerRadius = 8;
        preview.layer.borderWidth = 2;

        NSString *currentTheme = [[WAConfigManager sharedManager] objectForKey:@"currentTheme"];
        if ([themeNames[i] isEqualToString:currentTheme]) {
            preview.layer.borderColor = [[NSColor systemBlueColor] CGColor];
        } else {
            preview.layer.borderColor = [[NSColor separatorColor] CGColor];
        }

        NSTextField *themeLabel = [self labelWithText:themeNames[i] fontSize:11 bold:NO
                                                frame:NSMakeRect(0, 30, 100, 16)];
        themeLabel.alignment = NSTextAlignmentCenter;
        [preview addSubview:themeLabel];

        // 点击选择
        NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(themePreviewClicked:)];
        [preview addGestureRecognizer:click];

        [view addSubview:preview];
        x += 120;
    }

    return view;
}

- (NSView *)createAboutTabView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 400)];

    NSTextField *title = [self labelWithText:@"微信助手 WeChatAssistant" fontSize:18 bold:YES frame:NSMakeRect(20, 340, 400, 28)];
    [view addSubview:title];

    NSTextField *version = [self labelWithText:@"版本 1.0.0" fontSize:13 bold:NO frame:NSMakeRect(20, 315, 200, 20)];
    version.textColor = [NSColor secondaryLabelColor];
    [view addSubview:version];

    NSTextField *info = [self labelWithText:@"macOS 微信增强助手\n\n• 消息防撤回 - 保留被撤回的消息\n• 退群监控 - 实时监控群成员退出\n• 主题更换 - 自定义微信配色方案\n\n目标平台: Apple Silicon (M1/M2/M3/M4)\n微信版本: 4.1.x 系列\nmacOS 版本: 12.0+\n\n开源协议: AGPL-3.0"
                                  fontSize:12 bold:NO
                                     frame:NSMakeRect(20, 140, 500, 180)];
    info.textColor = [NSColor secondaryLabelColor];
    [view addSubview:info];

    return view;
}

#pragma mark - Actions

- (void)featureToggleChanged:(NSButton *)sender {
    NSArray *features = @[@"revokeProtection", @"groupMonitor", @"themeManager"];
    if (sender.tag < features.count) {
        NSString *featureName = features[sender.tag];
        [[WAConfigManager sharedManager] setFeature:featureName enabled:(sender.state == NSControlStateValueOn)];
    }
}

- (void)openRevokeHistory:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WAOpenRevokeHistory" object:nil];
}

- (void)clearRevokeHistory:(id)sender {
    // 由 WARevokeManager 处理
}

- (void)themePreviewClicked:(NSClickGestureRecognizer *)gesture {
    NSView *preview = gesture.view;
    NSTextField *label = preview.subviews.firstObject;
    if ([label isKindOfClass:[NSTextField class]]) {
        NSString *themeName = label.stringValue;
        WALogInfo(@"选择主题: %@", themeName);
        // 刷新预览边框
        for (NSView *v in preview.superview.subviews) {
            if ([v isKindOfClass:[NSView class]] && v != preview) {
                v.layer.borderColor = [[NSColor separatorColor] CGColor];
            }
        }
        preview.layer.borderColor = [[NSColor systemBlueColor] CGColor];
    }
}

#pragma mark - Helpers

- (NSTextField *)labelWithText:(NSString *)text fontSize:(CGFloat)size bold:(BOOL)bold frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    label.backgroundColor = [NSColor clearColor];
    label.bordered = NO;
    label.editable = NO;
    return label;
}

- (void)showWindow {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

@end
