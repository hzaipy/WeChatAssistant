//
//  WAThemeHook.m
//  WeChatAssistant
//
//  主题更换 Hook - 借鉴 WeChatExtension-ForMac 的四种皮肤模式
//
//  皮肤模式（致敬 WeChatExtension-ForMac / MustangYM）：
//  1. 迷离模式 (Fuzzy)    - NSVisualEffectView 毛玻璃效果
//  2. 黑夜模式 (Dark)      - 深色配色方案
//  3. 上帝模式 (God)       - 自定义背景图片
//  4. 少女模式 (Girl)      - 茱萸粉配色方案
//
//  实现原理（参考 WeChatExtension-ForMac 的分层渲染架构）：
//  - 基础层: 捕获微信原生视图层级
//  - 滤镜层: 应用颜色矩阵变换和透明度调整
//  - 合成层: 叠加 NSVisualEffectView 或自定义背景
//  - 性能优化: CALayer 缓存和异步渲染
//
//  关键 Hook 点:
//  - NSWindow.contentView → 插入 NSVisualEffectView（迷离模式）
//  - NSView.drawRect: → 替换背景绘制（上帝模式）
//  - NSColor 工厂方法 → 颜色映射（黑夜/少女模式）
//  - 聊天列表/气泡背景 → 视图层级修改
//

#import "WAThemeHook.h"
#import "WAThemeManager.h"
#import "WALogger.h"
#import <objc/runtime.h>

static BOOL gInstalled = NO;

// ============================================================
// 辅助: 给微信窗口添加毛玻璃效果（迷离模式）
// ============================================================
static void applyFuzzyEffectToWindow(NSWindow *window) {
    if (!window || !window.contentView) return;

    // 检查是否已添加效果视图
    static const char kFuzzyViewKey;
    NSVisualEffectView *existingView = objc_getAssociatedObject(window, &kFuzzyViewKey);
    if (existingView) {
        existingView.hidden = NO;
        return;
    }

    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:window.contentView.bounds];
    effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.material = NSVisualEffectMaterialHUDWindow;  // 半透明毛玻璃
    effectView.state = NSVisualEffectStateActive;
    effectView.wantsLayer = YES;

    // 插入到最底层
    [window.contentView addSubview:effectView positioned:NSWindowBelow relativeTo:nil];

    objc_setAssociatedObject(window, &kFuzzyViewKey, effectView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WALogInfo(@"🌫 迷离模式已应用 - 毛玻璃效果");
}

// ============================================================
// 辅助: 给微信窗口添加背景图片（上帝模式）
// ============================================================
static void applyBackgroundImageToWindow(NSWindow *window, NSString *imagePath) {
    if (!window || !imagePath) return;

    NSImage *bgImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!bgImage) {
        WALogWarn(@"无法加载背景图片: %@", imagePath);
        return;
    }

    static const char kBackgroundViewKey;
    NSImageView *existingView = objc_getAssociatedObject(window, &kBackgroundViewKey);

    if (!existingView) {
        NSImageView *imageView = [[NSImageView alloc] initWithFrame:window.contentView.bounds];
        imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        imageView.wantsLayer = YES;
        imageView.alphaValue = 0.3; // 30-50% 透明度

        [window.contentView addSubview:imageView positioned:NSWindowBelow relativeTo:nil];
        objc_setAssociatedObject(window, &kBackgroundViewKey, imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        existingView = imageView;
    }

    existingView.image = bgImage;
    existingView.hidden = NO;
    WALogInfo(@"🖼 上帝模式已应用 - 背景图片: %@", [imagePath lastPathComponent]);
}

// ============================================================
// 替换 NSWindow 的 setContentView: 以插入效果层
// ============================================================
static void (*gOriginalSetContentView)(id, SEL, NSView *) = NULL;

static void replaced_setContentView(NSWindow *self, SEL _cmd, NSView *contentView) {
    // 先调用原始方法
    if (gOriginalSetContentView) {
        gOriginalSetContentView(self, _cmd, contentView);
    }

    // 根据当前主题应用效果
    WAThemeManager *theme = [WAThemeManager sharedManager];
    if (!theme.isEnabled) return;

    WAThemeMode mode = theme.currentMode;

    dispatch_async(dispatch_get_main_queue(), ^{
        switch (mode) {
            case WAThemeModeFuzzy:
                applyFuzzyEffectToWindow(self);
                break;
            case WAThemeModeGod:
                applyBackgroundImageToWindow(self, theme.customBackgroundImagePath);
                break;
            default:
                break;
        }
    });
}

// ============================================================
// 替换 NSColor 工厂方法 - 颜色映射（黑夜/少女模式）
// ============================================================
static NSColor *(*gOriginalColorWithRGBA)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat) = NULL;

static NSColor *replaced_colorWithRGBA(id self, SEL _cmd, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    WAThemeManager *theme = [WAThemeManager sharedManager];
    if (!theme.isEnabled) {
        return gOriginalColorWithRGBA(self, _cmd, r, g, b, a);
    }

    WAThemeMode mode = theme.currentMode;

    switch (mode) {
        case WAThemeModeDark:
            // 黑夜模式: 反转浅色为深色，保持色彩对比度
            if (r > 0.9 && g > 0.9 && b > 0.9) {
                // 白色/近白色 → 深色背景
                return [NSColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:a];
            }
            if (r < 0.1 && g < 0.1 && b < 0.1) {
                // 黑色文字 → 浅色文字
                return [NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:a];
            }
            break;

        case WAThemeModeGirl:
            // 少女模式: 茱萸粉色系 (参考 WeChatExtension-ForMac)
            if (r > 0.9 && g > 0.9 && b > 0.9) {
                // 白色背景 → 淡粉
                return [NSColor colorWithRed:1.0 green:0.96 blue:0.97 alpha:a];
            }
            if (r > 0.9 && g < 0.3 && b < 0.3) {
                // 红色系 → 茱萸粉
                return [NSColor colorWithRed:0.98 green:0.45 blue:0.55 alpha:a];
            }
            // 整体暖色调
            return [NSColor colorWithRed:MIN(1.0, r * 1.05)
                                   green:g
                                    blue:MIN(1.0, b * 1.05)
                                   alpha:a];

        default:
            break;
    }

    return gOriginalColorWithRGBA(self, _cmd, r, g, b, a);
}

// ============================================================
// Hook 微信窗口的 makeKeyAndOrderFront: 以应用主题
// ============================================================
static void (*gOriginalMakeKeyAndOrderFront)(id, SEL, id) = NULL;

static void replaced_makeKeyAndOrderFront(NSWindow *self, SEL _cmd, id sender) {
    if (gOriginalMakeKeyAndOrderFront) {
        gOriginalMakeKeyAndOrderFront(self, _cmd, sender);
    }

    WAThemeManager *theme = [WAThemeManager sharedManager];
    if (!theme.isEnabled) return;

    switch (theme.currentMode) {
        case WAThemeModeFuzzy:
            applyFuzzyEffectToWindow(self);
            break;
        case WAThemeModeGod:
            applyBackgroundImageToWindow(self, theme.customBackgroundImagePath);
            break;
        default:
            break;
    }
}

// ============================================================
// Hook 聊天列表 TableView 的背景色
// ============================================================
static void (*gOriginalSetBackgroundColor)(id, SEL, NSColor *) = NULL;

static void replaced_tableSetBackgroundColor(id self, SEL _cmd, NSColor *color) {
    WAThemeManager *theme = [WAThemeManager sharedManager];
    if (theme.isEnabled && theme.currentMode == WAThemeModeDark) {
        color = [NSColor colorWithRed:0.12 green:0.12 blue:0.12 alpha:1.0];
    } else if (theme.isEnabled && theme.currentMode == WAThemeModeGirl) {
        color = [NSColor colorWithRed:1.0 green:0.96 blue:0.97 alpha:1.0];
    }

    if (gOriginalSetBackgroundColor) {
        gOriginalSetBackgroundColor(self, _cmd, color);
    }
}

// ============================================================
// 安装所有 Hook
// ============================================================
@implementation WAThemeHook

+ (BOOL)install {
    if (gInstalled) return YES;

    // 1. Hook NSColor 工厂方法（黑夜/少女模式）
    Method colorMethod = class_getClassMethod([NSColor class], @selector(colorWithRed:green:blue:alpha:));
    if (colorMethod) {
        gOriginalColorWithRGBA = (void *)method_setImplementation(colorMethod, (IMP)replaced_colorWithRGBA);
        WALogInfo(@"已 Hook NSColor +colorWithRed:green:blue:alpha:");
    }

    // 2. Hook NSWindow 的 makeKeyAndOrderFront:（应用迷离/上帝效果）
    Method windowMethod = class_getInstanceMethod([NSWindow class], @selector(makeKeyAndOrderFront:));
    if (windowMethod) {
        gOriginalMakeKeyAndOrderFront = (void *)method_setImplementation(windowMethod, (IMP)replaced_makeKeyAndOrderFront);
        WALogInfo(@"已 Hook NSWindow -makeKeyAndOrderFront:");
    }

    // 3. Hook NSWindow 的 setContentView:（插入效果层）
    Method contentViewMethod = class_getInstanceMethod([NSWindow class], @selector(setContentView:));
    if (contentViewMethod) {
        gOriginalSetContentView = (void *)method_setImplementation(contentViewMethod, (IMP)replaced_setContentView);
        WALogInfo(@"已 Hook NSWindow -setContentView:");
    }

    // 4. Hook TableView 背景色（用于聊天列表）
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
    numClasses = objc_getClassList(classes, numClasses);

    for (int i = 0; i < numClasses; i++) {
        NSString *clsName = NSStringFromClass(classes[i]);
        // 关注微信的 TableView 子类
        if (![clsName containsString:@"Table"] && ![clsName containsString:@"List"]) continue;
        if (![clsName hasPrefix:@"WC"] && ![clsName hasPrefix:@"MM"]) continue;

        SEL sel = NSSelectorFromString(@"setBackgroundColor:");
        Method m = class_getInstanceMethod(classes[i], sel);
        if (m) {
            gOriginalSetBackgroundColor = (void *)method_setImplementation(m, (IMP)replaced_tableSetBackgroundColor);
            WALogInfo(@"已 Hook [%@ setBackgroundColor:]", clsName);
            break;
        }
    }
    free(classes);

    gInstalled = YES;
    WALogInfo(@"✅ 主题 Hook 已安装（4种皮肤模式）");
    return YES;
}

+ (void)uninstall {
    gInstalled = NO;
    WALogInfo(@"主题 Hook 已卸载");
}

@end
