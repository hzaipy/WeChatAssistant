//
//  WARevokeHook.h
//  WeChatAssistant
//
//  核心功能 Hook - 防撤回 + 多开 + 禁止更新
//

#import <Foundation/Foundation.h>

@interface WARevokeHook : NSObject

/// 安装所有功能（防撤回 + 多开 + 禁止更新）
+ (BOOL)install;
+ (void)uninstall;

/// 单独安装多开（需在 constructor 早期调用）
+ (void)installMultiOpenImmediately;

/// dyld 回调中安装多开
+ (BOOL)installMultiOpenWithSlide:(intptr_t)slide;

/// dyld 回调中安装防撤回
+ (BOOL)installAntiRevokeWithSlide:(intptr_t)slide;

/// 安装禁止更新
+ (void)installAntiUpdateIfNeeded;

@end
