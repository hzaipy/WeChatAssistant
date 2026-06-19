//
//  WAThemeManager.h
//  WeChatAssistant
//
//  主题管理器 - 借鉴 WeChatExtension-ForMac 四种皮肤模式
//
//  皮肤模式:
//  - 迷离 (Fuzzy): NSVisualEffectView 毛玻璃
//  - 黑夜 (Dark):  深色配色
//  - 上帝 (God):   自定义背景图片
//  - 少女 (Girl):  茱萸粉配色
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// 皮肤模式枚举
typedef NS_ENUM(NSInteger, WAThemeMode) {
    WAThemeModeDefault = 0,  // 默认（无皮肤）
    WAThemeModeFuzzy,        // 迷离模式 - 毛玻璃
    WAThemeModeDark,         // 黑夜模式 - 深色
    WAThemeModeGod,          // 上帝模式 - 自定义背景
    WAThemeModeGirl,         // 少女模式 - 茱萸粉
};

@interface WAThemeManager : NSObject

+ (instancetype)sharedManager;

/// 是否启用主题
@property (nonatomic, assign, readonly) BOOL isEnabled;

/// 当前皮肤模式
@property (nonatomic, assign) WAThemeMode currentMode;

/// 当前主题名称
@property (nonatomic, copy, readonly) NSString *currentThemeName;

/// 自定义背景图片路径（上帝模式）
@property (nonatomic, copy) NSString *customBackgroundImagePath;

/// 加载当前配置
- (void)loadCurrentTheme;

/// 切换皮肤模式
- (void)switchToMode:(WAThemeMode)mode;
- (void)switchToThemeNamed:(NSString *)name;

/// 可用主题列表
- (NSArray<NSString *> *)availableThemeNames;

/// 模式名称
+ (NSString *)nameForMode:(WAThemeMode)mode;
+ (WAThemeMode)modeForName:(NSString *)name;

@end
