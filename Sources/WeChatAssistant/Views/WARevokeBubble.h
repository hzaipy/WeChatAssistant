//
//  WARevokeBubble.h
//  WeChatAssistant
//
//  撤回消息提示气泡视图
//

#import <Cocoa/Cocoa.h>

@interface WARevokeBubble : NSView

@property (nonatomic, copy) NSString *senderName;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, strong) NSDate *timestamp;

- (instancetype)initWithSenderName:(NSString *)senderName
                           content:(NSString *)content
                         timestamp:(NSDate *)timestamp;

@end
