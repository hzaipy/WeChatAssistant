//
//  WAHelper.h
//  WeChatAssistant
//
//  通用辅助方法
//

#import <Foundation/Foundation.h>

@interface WAHelper : NSObject

/// 获取微信版本号 (CFBundleVersion)
+ (NSString *)wechatVersion;

/// 获取微信用户数据目录
+ (NSString *)wechatDataDirectory;

/// 判断是否为 M 芯片 Mac
+ (BOOL)isAppleSilicon;

/// 安全执行 selector（避免找不到方法崩溃）
+ (id)safePerformSelector:(SEL)selector onObject:(id)object;

@end
