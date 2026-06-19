//
//  WAThemeManager.h
//  WeChatAssistant
//
//  主题管理器 - 加载、切换、管理主题
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface WATheme : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *colors; // key -> hex color
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *colorMappings; // 语义色 -> hex

+ (instancetype)themeWithDictionary:(NSDictionary *)dict;
+ (instancetype)themeWithName:(NSString *)name;

@end

@interface WAThemeManager : NSObject

+ (instancetype)sharedManager;

/// 是否启用主题
@property (nonatomic, assign, readonly) BOOL isEnabled;

/// 当前主题
@property (nonatomic, strong, readonly) WATheme *currentTheme;

/// 加载当前主题配置
- (void)loadCurrentTheme;

/// 切换到指定主题
- (void)switchToTheme:(NSString *)themeName;

/// 可用主题列表
- (NSArray<NSString *> *)availableThemes;

/// 颜色映射（被 WAThemeHook 调用）
- (NSColor *)mapColorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (NSColor *)mapBackgroundColor:(NSColor *)color;

/// 重新加载所有主题
- (void)reloadThemes;

@end
