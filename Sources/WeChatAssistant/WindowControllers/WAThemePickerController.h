//
//  WAThemePickerController.h
//  WeChatAssistant
//

#import <Cocoa/Cocoa.h>

@interface WAThemePickerController : NSWindowController
+ (instancetype)sharedController;
- (void)showWindow;
@end
