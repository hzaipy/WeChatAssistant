//
//  WARevokeHook.h
//  WeChatAssistant
//
//  防撤回 Hook - 拦截微信消息撤回事件
//

#import <Foundation/Foundation.h>

@interface WARevokeHook : NSObject

/// 安装防撤回 Hook
+ (BOOL)install;

/// 卸载
+ (void)uninstall;

@end
