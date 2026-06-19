//
//  WAThemePickerController.m
//  WeChatAssistant
//

#import "WAThemePickerController.h"
#import "WAThemeManager.h"

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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 350, 300)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = @"选择主题";
        [window center];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 260, 200, 20)];
    title.stringValue = @"选择主题";
    title.font = [NSFont boldSystemFontOfSize:14];
    title.backgroundColor = [NSColor clearColor];
    title.bordered = NO;
    title.editable = NO;
    [contentView addSubview:title];

    NSArray *themes = [[WAThemeManager sharedManager] availableThemes];
    CGFloat y = 230;
    for (NSString *themeName in themes) {
        NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 200, 28)];
        btn.title = themeName;
        btn.bezelStyle = NSBezelStyleRounded;
        btn.target = self;
        btn.action = @selector(selectTheme:);
        [contentView addSubview:btn];
        y -= 35;
    }
}

- (void)selectTheme:(NSButton *)sender {
    [[WAThemeManager sharedManager] switchToTheme:sender.title];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"主题已切换";
    alert.informativeText = [NSString stringWithFormat:@"已切换到「%@」主题，重启微信后生效。", sender.title];
    [alert addButtonWithTitle:@"好的"];
    [alert runModal];

    [self.window close];
}

- (void)showWindow {
    [self.window makeKeyAndOrderFront:nil];
}

@end
