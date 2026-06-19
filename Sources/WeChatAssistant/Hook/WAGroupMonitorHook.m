//
//  WAGroupMonitorHook.m
//  WeChatAssistant
//
//  退群监控实现
//
//  微信 4.1.x 中群成员变更的可能入口：
//  1. 群管理类: GroupMgr / CGroupMgr / WCGroupMgr
//  2. 群成员变更回调: onGroupMemberChange / handleGroupMemberChange
//  3. 系统通知: kGroupMemberChangedNotification
//  4. 群事件消息: GroupEventMessage / WCGroupEvent
//

#import "WAGroupMonitorHook.h"
#import "WAGroupMonitorManager.h"
#import "WALogger.h"
#import <objc/runtime.h>

static BOOL gInstalled = NO;
static IMP gOriginalGroupMemberChangeIMP = NULL;
static IMP gOriginalGroupEventIMP = NULL;

// ============================================================
// 替换后的群成员变更处理
// ============================================================
static void replaced_group_member_change(id self, SEL _cmd, id groupInfo, id memberInfo, NSInteger changeType) {
    WALogInfo(@"👥 检测到群成员变更: group=%@ changeType=%ld", groupInfo, (long)changeType);

    // changeType: 0=加入, 1=退出, 2=被踢
    NSString *groupName = nil;
    NSString *memberName = nil;

    @try {
        if ([groupInfo respondsToSelector:@selector(name)]) {
            groupName = [groupInfo valueForKey:@"name"];
        }
        if ([memberInfo respondsToSelector:@selector(nickname)]) {
            memberName = [memberInfo valueForKey:@"nickname"];
        }
        if ([memberInfo respondsToSelector:@selector(displayName)]) {
            memberName = [memberInfo valueForKey:@"displayName"];
        }
    } @catch (NSException *e) {
        WALogWarn(@"提取群成员信息异常: %@", e);
    }

    // 记录退群事件
    if (changeType == 1 || changeType == 2) { // 退出或被踢
        NSString *eventType = (changeType == 1) ? @"退出群聊" : @"被移出群聊";
        [[WAGroupMonitorManager sharedManager] recordGroupEvent:eventType
                                                      groupName:groupName
                                                     memberName:memberName
                                                     changeType:changeType];
        WALogInfo(@"📤 %@ %@ 在群「%@」%@", memberName ?: @"未知", eventType, groupName ?: @"未知",
                  changeType == 2 ? @"（被踢）" : @"");
    }

    // 调用原始实现（不阻止微信正常的群成员变更处理）
    if (gOriginalGroupMemberChangeIMP) {
        ((void(*)(id, SEL, id, id, NSInteger))gOriginalGroupMemberChangeIMP)(self, _cmd, groupInfo, memberInfo, changeType);
    }
}

// ============================================================
// 备用：群事件消息处理
// ============================================================
static void replaced_group_event(id self, SEL _cmd, id eventMessage) {
    WALogInfo(@"📨 收到群事件消息: %@", eventMessage);

    @try {
        // 尝试提取事件信息
        NSString *eventType = nil;
        if ([eventMessage respondsToSelector:@selector(eventType)]) {
            NSInteger type = [[eventMessage valueForKey:@"eventType"] integerValue];
            eventType = [self eventTypeDescription:type];
        }

        NSString *groupName = nil;
        if ([eventMessage respondsToSelector:@selector(groupName)]) {
            groupName = [eventMessage valueForKey:@"groupName"];
        }

        if (eventType) {
            [[WAGroupMonitorManager sharedManager] recordGroupEvent:eventType
                                                          groupName:groupName
                                                         memberName:nil
                                                         changeType:0];
        }
    } @catch (NSException *e) {
        WALogWarn(@"处理群事件消息异常: %@", e);
    }

    // 继续原始处理
    if (gOriginalGroupEventIMP) {
        ((void(*)(id, SEL, id))gOriginalGroupEventIMP)(self, _cmd, eventMessage);
    }
}

+ (NSString *)eventTypeDescription:(NSInteger)type {
    switch (type) {
        case 1: return @"成员加入";
        case 2: return @"成员退出";
        case 3: return @"被移出群聊";
        case 4: return @"群名变更";
        case 5: return @"群公告更新";
        default: return [NSString stringWithFormat:@"群事件(%ld)", (long)type];
    }
}

// ============================================================
@implementation WAGroupMonitorHook

+ (BOOL)install {
    if (gInstalled) return YES;

    BOOL hooked = NO;

    // 尝试 Hook 群成员变更方法
    NSArray *groupClasses = @[@"GroupMgr", @"CGroupMgr", @"WCGroupMgr",
                               @"MMGroupMgr", @"GroupService"];
    NSArray *memberChangeSelectors = @[@"onGroupMemberChange:member:type:",
                                        @"handleGroupMemberChange:member:changeType:",
                                        @"onGroupMemberChanged:"];

    for (NSString *clsName in groupClasses) {
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;

        for (NSString *selName in memberChangeSelectors) {
            SEL sel = NSSelectorFromString(selName);
            Method method = class_getInstanceMethod(cls, sel);
            if (!method) method = class_getClassMethod(cls, sel);
            if (!method) continue;

            gOriginalGroupMemberChangeIMP = method_setImplementation(method, (IMP)replaced_group_member_change);
            WALogInfo(@"✅ 退群监控 Hook 成功: [%@ %@]", clsName, selName);
            hooked = YES;
            break;
        }
        if (hooked) break;
    }

    // 尝试 Hook 群事件消息处理
    if (!hooked) {
        for (NSString *clsName in @[@"WCGroupEvent", @"GroupEventMessage", @"MMGroupEvent"]) {
            Class cls = NSClassFromString(clsName);
            if (!cls) continue;

            SEL sel = NSSelectorFromString(@"processEvent:");
            Method method = class_getInstanceMethod(cls, sel);
            if (method) {
                gOriginalGroupEventIMP = method_setImplementation(method, (IMP)replaced_group_event);
                WALogInfo(@"✅ 退群监控 Hook 成功 (群事件): [%@ %@]", clsName, @"processEvent:");
                hooked = YES;
                break;
            }
        }
    }

    if (!hooked) {
        // 动态搜索包含 "Group" 和 "Member" 关键词的方法
        int numClasses = objc_getClassList(NULL, 0);
        Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
        numClasses = objc_getClassList(classes, numClasses);

        for (int i = 0; i < numClasses && !hooked; i++) {
            NSString *clsName = NSStringFromClass(classes[i]);
            if (![clsName containsString:@"Group"]) continue;

            unsigned int count = 0;
            Method *methods = class_copyMethodList(classes[i], &count);
            for (unsigned int j = 0; j < count; j++) {
                NSString *mName = NSStringFromSelector(method_getName(methods[j]));
                if (([mName containsString:@"Group"] && [mName containsString:@"Member"]) ||
                    [mName containsString:@"memberChange"]) {
                    gOriginalGroupMemberChangeIMP = method_setImplementation(
                        methods[j], (IMP)replaced_group_member_change);
                    WALogInfo(@"✅ 退群监控 Hook 成功 (动态): [%@ %@]", clsName, mName);
                    hooked = YES;
                    break;
                }
            }
            free(methods);
        }
        free(classes);
    }

    gInstalled = hooked;
    if (!hooked) {
        WALogWarn(@"退群监控 Hook 未找到目标方法，将仅监听通知");
    }
    return YES; // 即使 Hook 失败也返回 YES，Manager 层面还有通知兜底
}

+ (void)uninstall {
    gInstalled = NO;
    WALogInfo(@"退群监控 Hook 已卸载");
}

@end
