//
//  WARevokeHook.m
//  WeChatAssistant
//
//  防撤回实现
//
//  策略说明：
//  微信 4.1.x 基于 QT/C++，防撤回的核心思路是拦截消息撤回通知的处理。
//
//  方案一（优先）：通过 Runtime 查找消息服务类中处理撤回的方法并 Swizzle
//  方案二（备用）：通知拦截 - 监听撤回相关的 NSNotification
//  方案三（最终）：二进制补丁 - 参考 WeChatTweak 的 arm64 汇编补丁
//
//  目标类（需根据具体版本调整）：
//  - MessageService / WCMessageService
//  - 撤回处理方法: onRevokeMsg / handleRevokeMsg / processRevokeMessage
//

#import "WARevokeHook.h"
#import "WARevokeManager.h"
#import "WALogger.h"
#import <objc/runtime.h>

// 保存原始 IMP
static IMP gOriginalRevokeIMP = NULL;
static BOOL gInstalled = NO;

// ============================================================
// 替换后的撤回处理函数
// ============================================================
static void replaced_revoke_handler(id self, SEL _cmd, id revokeMessage) {
    WALogInfo(@"🔄 拦截到撤回消息: %@", revokeMessage);

    // 1. 提取消息内容
    NSString *msgId = nil;
    NSString *content = nil;
    NSString *sender = nil;
    NSDate *timestamp = [NSDate date];

    // 尝试从消息对象中提取信息
    if (revokeMessage) {
        // 微信 4.1.x 消息对象可能包含以下属性
        @try {
            if ([revokeMessage respondsToSelector:@selector(msgId)]) {
                msgId = [revokeMessage valueForKey:@"msgId"];
            }
            if ([revokeMessage respondsToSelector:@selector(content)]) {
                content = [revokeMessage valueForKey:@"content"];
            }
            if ([revokeMessage respondsToSelector:@selector(sender)]) {
                sender = [revokeMessage valueForKey:@"sender"];
            }
            if ([revokeMessage respondsToSelector:@selector(createTime)]) {
                timestamp = [revokeMessage valueForKey:@"createTime"];
            }
        } @catch (NSException *e) {
            WALogWarn(@"提取消息信息异常: %@", e);
        }
    }

    // 2. 保存到撤回管理器
    if (content || msgId) {
        [[WARevokeManager sharedManager] recordRevokedMessage:content
                                                     sender:sender
                                                     msgId:msgId
                                                 timestamp:timestamp];
    }

    // 3. 不再调用原始实现，阻止消息被删除
    // 注意：不调用 gOriginalRevokeIMP(self, _cmd, revokeMessage)
    // 这样微信就不会从聊天记录中删除这条消息

    WALogInfo(@"✅ 消息已保留，未执行撤回删除");
}

// ============================================================
// 备用方案：通过通知拦截
// ============================================================
static void notification_revoke_handler(CFNotificationCenterRef center,
                                        void *observer,
                                        CFStringRef name,
                                        const void *object,
                                        CFDictionaryRef userInfo) {
    NSString *notifName = (__bridge NSString *)name;
    WALogInfo(@"🔔 收到撤回相关通知: %@", notifName);

    // 拦截通知，不让微信处理
    // 注意：CFNotificationCenter 的 observer 方式只能监听，不能阻止
    // 这个方法主要用于调试和发现撤回通知的名称
}

// ============================================================
// 实现
// ============================================================
@implementation WARevokeHook

+ (BOOL)install {
    if (gInstalled) return YES;

    // 尝试方法一：Runtime Swizzle
    BOOL hooked = [self installViaSwizzle];
    if (hooked) {
        gInstalled = YES;
        return YES;
    }

    // 尝试方法二：通知监听（作为调试辅助）
    [self installViaNotification];

    WALogInfo(@"防撤回: 使用通知监听模式（调试辅助）");
    gInstalled = YES;
    return YES;
}

+ (BOOL)installViaSwizzle {
    // 微信 4.1.x 中可能的消息服务类名
    NSArray *candidateClasses = @[
        @"MessageService",
        @"WCMessageService",
        @"MMMessageService",
        @"CMMessageService",
        @"MessageMgr"
    ];

    // 可能的撤回处理方法
    NSArray *candidateSelectors = @[
        @"onRevokeMsg:",
        @"handleRevokeMsg:",
        @"processRevokeMessage:",
        @"revokeMessage:",
        @"onRevokeMessage:"
    ];

    for (NSString *className in candidateClasses) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;

        for (NSString *selName in candidateSelectors) {
            SEL sel = NSSelectorFromString(selName);
            Method method = class_getInstanceMethod(cls, sel);
            if (!method) {
                method = class_getClassMethod(cls, sel);
            }
            if (!method) continue;

            IMP newIMP = (IMP)replaced_revoke_handler;
            gOriginalRevokeIMP = method_setImplementation(method, newIMP);

            WALogInfo(@"✅ 防撤回 Hook 成功: [%@ %@]", className, selName);
            return YES;
        }
    }

    // 动态搜索所有类中可能包含 "revoke" 的方法
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        Class cls = classes[i];
        NSString *clsName = NSStringFromClass(cls);

        // 过滤：只关注微信相关类
        if (![clsName hasPrefix:@"WC"] &&
            ![clsName hasPrefix:@"MM"] &&
            ![clsName hasPrefix:@"CMM"] &&
            ![clsName containsString:@"Message"] &&
            ![clsName containsString:@"Revoke"]) {
            continue;
        }

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int j = 0; j < methodCount; j++) {
            NSString *methodName = NSStringFromSelector(method_getName(methods[j]));
            if ([methodName.lowercaseString containsString:@"revoke"]) {
                SEL sel = method_getName(methods[j]);
                IMP newIMP = (IMP)replaced_revoke_handler;
                gOriginalRevokeIMP = method_setImplementation(methods[j], newIMP);
                WALogInfo(@"✅ 防撤回 Hook 成功 (动态发现): [%@ %@]", clsName, methodName);
                free(methods);
                free(classes);
                return YES;
            }
        }
        free(methods);
    }
    free(classes);

    WALogWarn(@"未找到撤回相关方法，Swizzle 方案失败");
    return NO;
}

+ (void)installViaNotification {
    // 监听可能的撤回相关通知
    // 微信 4.1.x 可能发送的撤回通知名称
    NSArray *possibleNames = @[
        @"WCMessageRevokeNotification",
        @"MMMessageRevokeNotification",
        @"MessageRevokeNotification",
        @"kMessageRevokeNotification",
    ];

    CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
    for (NSString *name in possibleNames) {
        CFNotificationCenterAddObserver(center,
                                        (__bridge void *)self,
                                        notification_revoke_handler,
                                        (__bridge CFStringRef)name,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        WALogDebug(@"注册通知监听: %@", name);
    }
}

+ (void)uninstall {
    // Swizzle 无法安全还原，但可以禁用功能逻辑
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetLocalCenter(),
                                            (__bridge void *)self);
    gInstalled = NO;
    WALogInfo(@"防撤回 Hook 已卸载");
}

@end
