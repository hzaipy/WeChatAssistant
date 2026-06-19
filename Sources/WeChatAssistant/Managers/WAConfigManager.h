//
//  WAConfigManager.h
//  WeChatAssistant
//
//  配置管理器 - 管理功能开关和用户偏好
//

#import <Foundation/Foundation.h>

@interface WAConfigManager : NSObject

+ (instancetype)sharedManager;

/// 加载配置
- (void)loadConfig;

/// 保存配置
- (void)saveConfig;

/// 功能开关
- (BOOL)isFeatureEnabled:(NSString *)featureName;
- (BOOL)toggleFeature:(NSString *)featureName;
- (void)setFeature:(NSString *)featureName enabled:(BOOL)enabled;

/// 获取配置值
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;

/// 配置描述
- (NSString *)description;

@end
