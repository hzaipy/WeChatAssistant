//
//  WAHookManager.h
//  WeChatAssistant
//
//  Hook 管理器 - 统一管理所有 Method Swizzling 和二进制补丁
//

#import <Foundation/Foundation.h>

@interface WAHookManager : NSObject

+ (instancetype)sharedManager;

/// 安装所有 Hook
- (void)installAllHooks;

/// 仅安装安全 Hook（不包含内存补丁类的：防撤回、多开）
- (void)installSafeHooks;

/// 卸载所有 Hook
- (void)uninstallAllHooks;

/// 动态 Hook 某个方法
- (BOOL)hookClass:(NSString *)className
         selector:(SEL)originalSelector
     replacement:(IMP)replacementIMP
     originalIMP:(IMP *)originalIMP;

@end
