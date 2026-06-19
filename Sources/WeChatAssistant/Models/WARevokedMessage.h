//
//  WARevokedMessage.h
//  WeChatAssistant
//

#import <Foundation/Foundation.h>

@interface WARevokedMessage : NSObject

@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) NSString *senderName;
@property (nonatomic, copy) NSString *contactId;
@property (nonatomic, strong) NSDate *originalTime;
@property (nonatomic, strong) NSDate *revokeTime;
@property (nonatomic, assign) NSInteger messageType; // 0=文本, 1=图片, 2=语音, 3=视频

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
- (NSString *)formattedDescription;

@end
