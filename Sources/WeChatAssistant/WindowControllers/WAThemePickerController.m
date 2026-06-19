//
//  WAThemePickerController.m
//  WeChatAssistant
//
//  主题选择器 - 四种皮肤模式预览
//  借鉴 WeChatExtension-ForMac 的皮肤 UI
//

#import "WAThemePickerController.h"
#import "WAThemeManager.h"
#import "WALogger.h"

@implementation WAThemePickerController

+ (instancetype)sharedController {
    static WAThemePickerController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAThemePickerController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 380)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = @"选择皮肤模式";
        [window center];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    NSTextField *title = [self label:@"选择皮肤模式" fontSize:16 bold:YES
                               frame:NSMakeRect(20, 340, 200, 24)];
    [contentView addSubview:title];

    NSTextField *subtitle = [self label:@"切换后重启微信生效  ·  致敬 WeChatExtension-ForMac"
                               fontSize:11 bold:NO
                                 frame:NSMakeRect(20, 320, 400, 16)];
    subtitle.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:subtitle];

    // 四种皮肤模式预览卡片
    NSArray *modes = @[
        @{@"name": @"迷离模式", @"icon": @"🌫", @"desc": @"半透明毛玻璃效果\n朦胧梦幻质感",
          @"mode": @(WAThemeModeFuzzy), @"color": [NSColor colorWithRed:0.8 green:0.85 blue:0.9 alpha:0.6]},
        @{@"name": @"黑夜模式", @"icon": @"🌙", @"desc": @"深色背景 · 高对比度\n夜间护眼 · 减少蓝光",
          @"mode": @(WAThemeModeDark), @"color": [NSColor colorWithRed:0.12 green:0.12 blue:0.12 alpha:1.0]},
        @{@"name": @"上帝模式", @"icon": @"🖼", @"desc": @"自定义背景图片\n打造专属聊天空间",
          @"mode": @(WAThemeModeGod), @"color": [NSColor colorWithRed:0.5 green:0.6 blue:0.7 alpha:1.0]},
        @{@"name": @"少女模式", @"icon": @"🌸", @"desc": @"茱萸粉配色方案\n温馨甜美 · 活力青春",
          @"mode": @(WAThemeModeGirl), @"color": [NSColor colorWithRed:1.0 green:0.88 blue:0.90 alpha:1.0]},
    ];

    CGFloat x = 20;
    CGFloat y = 60;
    CGFloat cardW = 105;
    CGFloat cardH = 140;

    WAThemeMode currentMode = [WAThemeManager sharedManager].currentMode;

    for (NSDictionary *mode in modes) {
        NSView *card = [[NSView alloc] initWithFrame:NSMakeRect(x, y, cardW, cardH)];
        card.wantsLayer = YES;
        card.layer.cornerRadius = 12;
        card.layer.borderWidth = 2;

        WAThemeMode modeVal = [mode[@"mode"] integerValue];
        if (modeVal == currentMode) {
            card.layer.borderColor = [[NSColor systemBlueColor] CGColor];
        } else {
            card.layer.borderColor = [[NSColor separatorColor] CGColor];
        }

        // 颜色预览区
        NSView *preview = [[NSView alloc] initWithFrame:NSMakeRect(8, 55, cardW - 16, 50)];
        preview.wantsLayer = YES;
        preview.layer.backgroundColor = [mode[@"color"] CGColor];
        preview.layer.cornerRadius = 8;
        [card addSubview:preview];

        // 图标和名称
        NSTextField *iconLabel = [self label:mode[@"icon"] fontSize:24 bold:NO
                                       frame:NSMakeRect(0, 105, cardW, 30)];
        iconLabel.alignment = NSTextAlignmentCenter;
        [card addSubview:iconLabel];

        NSTextField *nameLabel = [self label:mode[@"name"] fontSize:12 bold:YES
                                       frame:NSMakeRect(0, 40, cardW, 18)];
        nameLabel.alignment = NSTextAlignmentCenter;
        [card addSubview:nameLabel];

        // 描述
        NSTextField *descLabel = [self label:mode[@"desc"] fontSize:9 bold:NO
                                       frame:NSMakeRect(5, 0, cardW - 10, 38)];
        descLabel.alignment = NSTextAlignmentCenter;
        descLabel.textColor = [NSColor secondaryLabelColor];
        [card addSubview:descLabel];

        // 点击手势
        NSClickGestureRecognizer *click = [[NSClickGestureRecognizer alloc]
            initWithTarget:self action:@selector(cardClicked:)];
        [card addGestureRecognizer:click];

        // 存储 mode 值
        objc_setAssociatedObject(card, "mode", mode[@"mode"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [contentView addSubview:card];
        x += cardW + 12;
    }

    // 上帝模式的图片选择按钮
    if (currentMode == WAThemeModeGod) {
        NSButton *chooseImageBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 20, 150, 28)];
        chooseImageBtn.title = @"选择背景图片...";
        chooseImageBtn.bezelStyle = NSBezelStyleRounded;
        chooseImageBtn.target = self;
        chooseImageBtn.action = @selector(chooseBackgroundImage:);
        [contentView addSubview:chooseImageBtn];
    }
}

- (void)cardClicked:(NSClickGestureRecognizer *)gesture {
    NSView *card = gesture.view;
    NSNumber *modeNum = objc_getAssociatedObject(card, "mode");
    WAThemeMode mode = [modeNum integerValue];

    [[WAThemeManager sharedManager] switchToMode:mode];

    // 刷新选中状态
    for (NSView *v in card.superview.subviews) {
        if (v.wantsLayer) {
            v.layer.borderColor = (v == card)
                ? [[NSColor systemBlueColor] CGColor]
                : [[NSColor separatorColor] CGColor];
        }
    }

    // 上帝模式特殊处理
    if (mode == WAThemeModeGod) {
        [self chooseBackgroundImage:nil];
    }

    // 提示重启
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"皮肤模式已切换";
    alert.informativeText = [NSString stringWithFormat:@"已切换到「%@」，重启微信后生效。",
                             [WAThemeManager nameForMode:mode]];
    [alert addButtonWithTitle:@"稍后重启"];
    [alert addButtonWithTitle:@"立即重启"];
    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertSecondButtonReturn) {
        system("killall WeChat && open /Applications/WeChat.app");
    }
}

- (void)chooseBackgroundImage:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择背景图片";
    panel.allowedFileTypes = @[@"png", @"jpg", @"jpeg", @"heic", @"webp"];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSString *path = panel.URL.path;
            [WAThemeManager sharedManager].customBackgroundImagePath = path;
            [[WAConfigManager sharedManager] setObject:path forKey:@"customBackgroundPath"];
            WALogInfo(@"背景图片已选择: %@", path);
        }
    }];
}

- (NSTextField *)label:(NSString *)text fontSize:(CGFloat)size bold:(BOOL)bold frame:(NSRect)frame {
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
}

@end
