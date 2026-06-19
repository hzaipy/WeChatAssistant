//
//  WANotificationView.m
//  WeChatAssistant
//

#import "WANotificationView.h"

@implementation WANotificationView

+ (void)showNotificationWithTitle:(NSString *)title
                           message:(NSString *)message
                          duration:(NSTimeInterval)duration {

    dispatch_async(dispatch_get_main_queue(), ^{
        // 获取当前 key window
        NSWindow *keyWindow = [NSApp keyWindow];
        if (!keyWindow) return;

        NSView *contentView = keyWindow.contentView;
        CGFloat width = 300;
        CGFloat height = 60;

        WANotificationView *notification = [[WANotificationView alloc]
            initWithFrame:NSMakeRect(contentView.bounds.size.width - width - 20,
                                      contentView.bounds.size.height - height - 20,
                                      width, height)];

        notification.wantsLayer = YES;
        notification.layer.backgroundColor = [[NSColor colorWithWhite:0.15 alpha:0.9] CGColor];
        notification.layer.cornerRadius = 10;
        notification.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;

        NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 34, width - 32, 18)];
        titleLabel.stringValue = title;
        titleLabel.font = [NSFont boldSystemFontOfSize:13];
        titleLabel.textColor = [NSColor whiteColor];
        titleLabel.backgroundColor = [NSColor clearColor];
        titleLabel.bordered = NO;
        titleLabel.editable = NO;
        [notification addSubview:titleLabel];

        NSTextField *msgLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 14, width - 32, 16)];
        msgLabel.stringValue = message;
        msgLabel.font = [NSFont systemFontOfSize:11];
        msgLabel.textColor = [NSColor colorWithWhite:0.8 alpha:1.0];
        msgLabel.backgroundColor = [NSColor clearColor];
        msgLabel.bordered = NO;
        msgLabel.editable = NO;
        [notification addSubview:msgLabel];

        [contentView addSubview:notification];

        // 动画淡入
        notification.alphaValue = 0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.3;
            notification.animator.alphaValue = 1.0;
        } completionHandler:nil];

        // 自动移除
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.5;
                notification.animator.alphaValue = 0;
            } completionHandler:^{
                [notification removeFromSuperview];
            }];
        });
    });
}

@end
