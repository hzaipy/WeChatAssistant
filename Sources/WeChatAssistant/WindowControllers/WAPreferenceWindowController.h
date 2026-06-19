//
//  WAPreferenceWindowController.h
//  WeChatAssistant
//
//  偏好设置窗口控制器
//

#import <Cocoa/Cocoa.h>

@interface WAPreferenceWindowController : NSWindowController

+ (instancetype)sharedController;
- (void)showWindow;

@end
