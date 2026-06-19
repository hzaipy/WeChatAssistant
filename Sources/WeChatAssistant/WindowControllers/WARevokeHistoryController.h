//
//  WARevokeHistoryController.h
//  WeChatAssistant
//

#import <Cocoa/Cocoa.h>

@interface WARevokeHistoryController : NSWindowController
+ (instancetype)sharedController;
- (void)showWindow;
- (void)refreshData;
@end
