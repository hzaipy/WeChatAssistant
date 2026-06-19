//
//  WANotificationView.h
//  WeChatAssistant
//
//  通知横幅视图
//

#import <Cocoa/Cocoa.h>

@interface WANotificationView : NSView

+ (void)showNotificationWithTitle:(NSString *)title
                           message:(NSString *)message
                          duration:(NSTimeInterval)duration;

@end
