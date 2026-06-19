//
//  WAThemeManager.m
//  WeChatAssistant
//
//  主题管理器实现
//  借鉴 WeChatExtension-ForMac 的四种皮肤模式
//

#import "WAThemeManager.h"
#import "WAConfigManager.h"
#import "WALogger.h"

@implementation WAThemeManager

+ (instancetype)sharedManager {
    static WAThemeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAThemeManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentMode = WAThemeModeDefault;
        _isEnabled = YES;
    }
    return self;
}

- (void)loadCurrentTheme {
    self.isEnabled = [[WAConfigManager sharedManager] isFeatureEnabled:@"themeManager"];

    NSString *savedMode = [[WAConfigManager sharedManager] objectForKey:@"currentThemeMode"];
    if (savedMode) {
        self.currentMode = [WAThemeManager modeForName:savedMode];
    } else {
        self.currentMode = WAThemeModeDefault;
    }

    // 加载自定义背景图路径
    self.customBackgroundImagePath = [[WAConfigManager sharedManager] objectForKey:@"customBackgroundPath"];

    WALogInfo(@"当前主题: %@", [WAThemeManager nameForMode:self.currentMode]);
}

- (NSString *)currentThemeName {
    return [WAThemeManager nameForMode:self.currentMode];
}

- (void)switchToMode:(WAThemeMode)mode {
    self.currentMode = mode;
    [[WAConfigManager sharedManager] setObject:[WAThemeManager nameForMode:mode]
                                        forKey:@"currentThemeMode"];

    // 发送主题变更通知
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WAThemeDidChangeNotification"
                                                        object:nil
                                                      userInfo:@{
        @"themeMode": @(mode),
        @"themeName": [WAThemeManager nameForMode:mode]
    }];

    WALogInfo(@"✅ 主题已切换为: %@", [WAThemeManager nameForMode:mode]);
}

- (void)switchToThemeNamed:(NSString *)name {
    WAThemeMode mode = [WAThemeManager modeForName:name];
    [self switchToMode:mode];
}

- (NSArray<NSString *> *)availableThemeNames {
    return @[
        @"默认",
        @"迷离模式 🌫",
        @"黑夜模式 🌙",
        @"上帝模式 🖼",
        @"少女模式 🌸"
    ];
}

+ (NSString *)nameForMode:(WAThemeMode)mode {
    switch (mode) {
        case WAThemeModeDefault: return @"默认";
        case WAThemeModeFuzzy:   return @"迷离模式";
        case WAThemeModeDark:    return @"黑夜模式";
        case WAThemeModeGod:     return @"上帝模式";
        case WAThemeModeGirl:    return @"少女模式";
    }
}

+ (WAThemeMode)modeForName:(NSString *)name {
    if ([name containsString:@"迷离"]) return WAThemeModeFuzzy;
    if ([name containsString:@"黑夜"]) return WAThemeModeDark;
    if ([name containsString:@"上帝"]) return WAThemeModeGod;
    if ([name containsString:@"少女"]) return WAThemeModeGirl;
    return WAThemeModeDefault;
}

@end
