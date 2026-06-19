//
//  WAThemeHook.m
//  WeChatAssistant
//
//  主题更换 Hook
//
//  微信 4.1.x 基于 QT，颜色管理可能部分通过 OC 桥接。
//  核心思路：
//  1. Hook NSColor/UIColor 的工厂方法，拦截颜色创建
//  2. Hook NSView 的 drawRect: 进行视图级别的颜色替换
//  3. 对特定微信颜色类进行 Swizzle
//
//  可能的目标类：
//  - MMColor / WCColor (微信自定义颜色类)
//  - NSColor (系统颜色类)
//  - 聊天气泡相关的 View 类
//

#import "WAThemeHook.h"
#import "WAThemeManager.h"
#import "WALogger.h"
#import <objc/runtime.h>

static BOOL gInstalled = NO;

// ============================================================
// 替换 NSColor 的 colorWithRed:green:blue:alpha:
// ============================================================
static NSColor *(*gOriginalColorWithRGBA)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat) = NULL;

static NSColor *replaced_colorWithRGBA(id self, SEL _cmd, CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    // 检查主题是否启用
    WAThemeManager *theme = [WAThemeManager sharedManager];
    if (!theme.isEnabled || !theme.currentTheme) {
        return gOriginalColorWithRGBA(self, _cmd, red, green, blue, alpha);
    }

    // 应用主题颜色映射
    NSColor *mappedColor = [theme mapColorWithRed:red green:green blue:blue alpha:alpha];
    if (mappedColor) {
        return mappedColor;
    }

    return gOriginalColorWithRGBA(self, _cmd, red, green, blue, alpha);
}

// ============================================================
// 替换 NSView 的背景色设置（用于全局背景色替换）
// ============================================================
static void (*gOriginalSetBackgroundColor)(id, SEL, NSColor *) = NULL;

static void replaced_setBackgroundColor(id self, SEL _cmd, NSColor *color) {
    WAThemeManager *theme = [WAThemeManager sharedManager];
    if (theme.isEnabled && theme.currentTheme) {
        NSColor *mappedColor = [theme mapBackgroundColor:color];
        if (mappedColor) {
            gOriginalSetBackgroundColor(self, _cmd, mappedColor);
            return;
        }
    }
    gOriginalSetBackgroundColor(self, _cmd, color);
}

// ============================================================
@implementation WAThemeHook

+ (BOOL)install {
    if (gInstalled) return YES;

    [self hookNSColorFactory];
    [self hookNSViewBackground];
    [self hookWeChatColorClass];

    gInstalled = YES;
    WALogInfo(@"✅ 主题 Hook 已安装");
    return YES;
}

+ (void)hookNSColorFactory {
    // Hook NSColor 的类方法 colorWithRed:green:blue:alpha:
    Method method = class_getClassMethod([NSColor class], @selector(colorWithRed:green:blue:alpha:));
    if (method) {
        gOriginalColorWithRGBA = (void *)method_setImplementation(method, (IMP)replaced_colorWithRGBA);
        WALogInfo(@"已 Hook NSColor +colorWithRed:green:blue:alpha:");
    }
}

+ (void)hookNSViewBackground {
    // Hook NSView 的 setBackgroundColor: (如果存在)
    // 注意：NSView 没有 backgroundColor 属性，这是针对微信自定义子类的
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        NSString *clsName = NSStringFromClass(classes[i]);

        // 只关注微信的 View 类
        if (![clsName hasPrefix:@"WC"] && ![clsName hasPrefix:@"MM"] &&
            ![clsName containsString:@"WeChat"] && ![clsName containsString:@"Message"]) {
            continue;
        }

        SEL sel = NSSelectorFromString(@"setBackgroundColor:");
        Method method = class_getInstanceMethod(classes[i], sel);
        if (method) {
            gOriginalSetBackgroundColor = (void *)method_setImplementation(method, (IMP)replaced_setBackgroundColor);
            WALogInfo(@"已 Hook [%@ setBackgroundColor:]", clsName);
            free(classes);
            return;
        }

        // 也尝试 setColor:
        sel = NSSelectorFromString(@"setColor:");
        method = class_getInstanceMethod(classes[i], sel);
        if (method) {
            gOriginalSetBackgroundColor = (void *)method_setImplementation(method, (IMP)replaced_setBackgroundColor);
            WALogInfo(@"已 Hook [%@ setColor:]", clsName);
            free(classes);
            return;
        }
    }
    free(classes);
}

+ (void)hookWeChatColorClass {
    // 尝试 Hook 微信自定义颜色类
    NSArray *colorClasses = @[@"MMColor", @"WCColor", @"WeChatColor", @"CMMColor"];

    for (NSString *clsName in colorClasses) {
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;

        // 尝试 Hook 颜色获取的类方法
        unsigned int count = 0;
        Method *methods = class_copyMethodList(object_getClass(cls), &count);
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            NSString *selName = NSStringFromSelector(sel);

            // 只关注返回 NSColor 的颜色获取方法
            if ([selName hasPrefix:@"color"] ||
                [selName containsString:@"Color"] ||
                [selName containsString:@"Background"] ||
                [selName containsString:@"Foreground"]) {

                // 获取方法返回类型
                char returnType[256];
                method_getReturnType(methods[i], returnType, sizeof(returnType));
                if (strcmp(returnType, "@") == 0) { // 返回对象类型
                    WALogDebug(@"发现颜色方法: +[%@ %@]", clsName, selName);
                }
            }
        }
        free(methods);
    }
}

+ (void)uninstall {
    gInstalled = NO;
    WALogInfo(@"主题 Hook 已卸载");
}

@end
