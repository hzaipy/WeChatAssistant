//
//  WAConfigManager.m
//  WeChatAssistant
//

#import "WAConfigManager.h"
#import "WALogger.h"

static NSString * const kConfigFileName = @"com.wechatassistant.config.plist";

@interface WAConfigManager ()
@property (nonatomic, strong) NSMutableDictionary *config;
@property (nonatomic, copy) NSString *configPath;
@end

@implementation WAConfigManager

+ (instancetype)sharedManager {
    static WAConfigManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAConfigManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSString *configDir = [appSupport stringByAppendingPathComponent:@"WeChatAssistant"];
        [[NSFileManager defaultManager] createDirectoryAtPath:configDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        _configPath = [configDir stringByAppendingPathComponent:kConfigFileName];
    }
    return self;
}

- (void)loadConfig {
    self.config = [NSMutableDictionary dictionaryWithContentsOfFile:self.configPath];
    if (!self.config) {
        // 默认配置
        self.config = [NSMutableDictionary dictionaryWithDictionary:@{
            @"revokeProtection": @YES,
            @"groupMonitor": @YES,
            @"themeManager": @YES,
            @"antiUpdate": @YES,
            @"multiOpen": @YES,
            @"currentTheme": @"默认",
            @"logLevel": @(WALogLevelInfo),
            @"autoLaunch": @NO,
            @"firstRun": @YES,
            @"version": @"1.0.0"
        }];
        [self saveConfig];
        WALogInfo(@"创建默认配置");
    }
    WALogInfo(@"配置已加载: %@", self.configPath);
}

- (void)saveConfig {
    [self.config writeToFile:self.configPath atomically:YES];
}

- (BOOL)isFeatureEnabled:(NSString *)featureName {
    NSNumber *val = self.config[featureName];
    return val ? [val boolValue] : NO;
}

- (BOOL)toggleFeature:(NSString *)featureName {
    BOOL current = [self isFeatureEnabled:featureName];
    [self setFeature:featureName enabled:!current];
    return !current;
}

- (void)setFeature:(NSString *)featureName enabled:(BOOL)enabled {
    self.config[featureName] = @(enabled);
    [self saveConfig];
    WALogInfo(@"功能 '%@' -> %@", featureName, enabled ? @"开启" : @"关闭");
}

- (id)objectForKey:(NSString *)key {
    return self.config[key];
}

- (void)setObject:(id)object forKey:(NSString *)key {
    if (object) {
        self.config[key] = object;
    } else {
        [self.config removeObjectForKey:key];
    }
    [self saveConfig];
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithFormat:@"<WAConfigManager v%@>\n", self.config[@"version"]];
    [desc appendFormat:@"  防撤回: %@\n", [self isFeatureEnabled:@"revokeProtection"] ? @"✅" : @"❌"];
    [desc appendFormat:@"  退群监控: %@\n", [self isFeatureEnabled:@"groupMonitor"] ? @"✅" : @"❌"];
    [desc appendFormat:@"  主题更换: %@\n", [self isFeatureEnabled:@"themeManager"] ? @"✅" : @"❌"];
    [desc appendFormat:@"  当前主题: %@\n", self.config[@"currentTheme"]];
    return desc;
}

@end
