//
//  WAThemeManager.m
//  WeChatAssistant
//

#import "WAThemeManager.h"
#import "WAConfigManager.h"
#import "WALogger.h"

#pragma mark - WATheme

@implementation WATheme

+ (instancetype)themeWithDictionary:(NSDictionary *)dict {
    WATheme *theme = [[WATheme alloc] init];
    theme.name = dict[@"name"] ?: @"Unnamed";
    theme.version = dict[@"version"] ?: @"1.0";
    theme.colors = dict[@"colors"] ?: @{};
    theme.colorMappings = dict[@"colorMappings"] ?: @{};
    return theme;
}

+ (instancetype)themeWithName:(NSString *)name {
    NSString *path = [self themePathForName:name];
    if (!path) return nil;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;

    NSError *error = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || !dict) return nil;

    return [self themeWithDictionary:dict];
}

+ (NSString *)themePathForName:(NSString *)name {
    // 1. 用户自定义主题
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *userThemePath = [[appSupport stringByAppendingPathComponent:@"WeChatAssistant/Themes"]
                               stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.theme/theme.json", name]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:userThemePath]) {
        return userThemePath;
    }

    // 2. 内置主题（在动态库 Resources 目录下）
    NSString *bundlePath = [[NSBundle bundleForClass:[self class]] resourcePath];
    NSString *builtinPath = [[bundlePath stringByAppendingPathComponent:@"Themes"]
                             stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.theme/theme.json", name]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:builtinPath]) {
        return builtinPath;
    }

    return nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<WATheme name=%@ version=%@ colors=%lu>",
            self.name, self.version, (unsigned long)self.colors.count];
}

@end

#pragma mark - WAThemeManager

@interface WAThemeManager ()
@property (nonatomic, strong, readwrite) WATheme *currentTheme;
@property (nonatomic, assign, readwrite) BOOL isEnabled;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WATheme *> *themeCache;
@end

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
        _themeCache = [NSMutableDictionary dictionary];
        _isEnabled = YES;
    }
    return self;
}

- (void)loadCurrentTheme {
    self.isEnabled = [[WAConfigManager sharedManager] isFeatureEnabled:@"themeManager"];

    NSString *currentThemeName = [[WAConfigManager sharedManager] objectForKey:@"currentTheme"];
    if (!currentThemeName) {
        currentThemeName = @"Default";
        [[WAConfigManager sharedManager] setObject:currentThemeName forKey:@"currentTheme"];
    }

    self.currentTheme = [self loadTheme:currentThemeName];
    if (!self.currentTheme) {
        // Fallback: 创建默认主题
        self.currentTheme = [self defaultTheme];
    }

    WALogInfo(@"当前主题: %@", self.currentTheme.name);
}

- (WATheme *)loadTheme:(NSString *)name {
    // 检查缓存
    WATheme *cached = self.themeCache[name];
    if (cached) return cached;

    WATheme *theme = [WATheme themeWithName:name];
    if (theme) {
        self.themeCache[name] = theme;
    }
    return theme;
}

- (void)switchToTheme:(NSString *)themeName {
    WATheme *theme = [self loadTheme:themeName];
    if (!theme) {
        WALogWarn(@"主题 '%@' 未找到", themeName);
        return;
    }

    self.currentTheme = theme;
    [[WAConfigManager sharedManager] setObject:themeName forKey:@"currentTheme"];

    // 发送主题变更通知
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WAThemeDidChangeNotification"
                                                        object:nil
                                                      userInfo:@{@"themeName": themeName}];

    WALogInfo(@"✅ 主题已切换为: %@", themeName);
}

- (NSArray<NSString *> *)availableThemes {
    NSMutableArray *themes = [NSMutableArray array];

    // 内置主题
    NSString *bundlePath = [[NSBundle bundleForClass:[self class]] resourcePath];
    NSString *themesDir = [bundlePath stringByAppendingPathComponent:@"Themes"];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:themesDir error:nil];
    for (NSString *item in contents) {
        if ([item hasSuffix:@".theme"]) {
            NSString *name = [item stringByDeletingPathExtension];
            if (![themes containsObject:name]) {
                [themes addObject:name];
            }
        }
    }

    // 用户自定义主题
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *userThemesDir = [appSupport stringByAppendingPathComponent:@"WeChatAssistant/Themes"];
    contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:userThemesDir error:nil];
    for (NSString *item in contents) {
        if ([item hasSuffix:@".theme"]) {
            NSString *name = [item stringByDeletingPathExtension];
            if (![themes containsObject:name]) {
                [themes addObject:name];
            }
        }
    }

    return themes.count > 0 ? themes : @[@"Default", @"Dark", @"Minimal"];
}

- (NSColor *)mapColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha {
    if (!self.isEnabled || !self.currentTheme) return nil;

    // 如果当前是默认主题，不做映射
    if ([self.currentTheme.name isEqualToString:@"Default"]) return nil;

    NSDictionary *mappings = self.currentTheme.colorMappings;
    if (mappings.count == 0) return nil;

    // 将 RGB 转为 hex 字符串进行匹配
    NSString *hexKey = [NSString stringWithFormat:@"#%02X%02X%02X",
                        (int)(red * 255), (int)(green * 255), (int)(blue * 255)];

    NSString *mappedHex = mappings[hexKey];
    if (mappedHex) {
        return [self colorFromHex:mappedHex alpha:alpha];
    }

    return nil;
}

- (NSColor *)mapBackgroundColor:(NSColor *)color {
    if (!self.isEnabled || !self.currentTheme) return nil;

    NSDictionary *semanticColors = self.currentTheme.colors;
    if (semanticColors.count == 0) return nil;

    // 通过语义色映射背景色
    // 检测是否为接近白色（背景色）
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];

    if (r > 0.9 && g > 0.9 && b > 0.9) {
        // 浅色背景 -> 主题背景色
        NSString *bgHex = semanticColors[@"background"];
        if (bgHex) return [self colorFromHex:bgHex alpha:a];
    }
    if (r < 0.15 && g < 0.15 && b < 0.15) {
        // 深色背景 -> 主题深色背景
        NSString *darkBgHex = semanticColors[@"darkBackground"];
        if (darkBgHex) return [self colorFromHex:darkBgHex alpha:a];
    }

    return nil;
}

- (NSColor *)colorFromHex:(NSString *)hex alpha:(CGFloat)alpha {
    NSString *cleanHex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (cleanHex.length != 6) return nil;

    unsigned int rgb = 0;
    [[NSScanner scannerWithString:cleanHex] scanHexInt:&rgb];

    return [NSColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

- (WATheme *)defaultTheme {
    return [WATheme themeWithDictionary:@{
        @"name": @"Default",
        @"version": @"1.0",
        @"colors": @{
            @"background": @"#F5F5F5",
            @"chatBubbleSelf": @"#95EC69",
            @"chatBubbleOther": @"#FFFFFF",
            @"textPrimary": @"#000000",
            @"textSecondary": @"#888888",
            @"sidebarBackground": @"#E8E8E8",
            @"darkBackground": @"#2C2C2C"
        }
    }];
}

- (void)reloadThemes {
    [self.themeCache removeAllObjects];
    [self loadCurrentTheme];
    WALogInfo(@"主题已重新加载");
}

@end
