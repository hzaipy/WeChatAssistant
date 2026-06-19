//
//  WARevokedMessage.m
//  WeChatAssistant
//

#import "WARevokedMessage.h"

@implementation WARevokedMessage

- (instancetype)init {
    self = [super init];
    if (self) {
        _revokeTime = [NSDate date];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _messageId = dict[@"msg_id"] ?: dict[@"messageId"];
        _content = dict[@"content"];
        _senderName = dict[@"sender"] ?: dict[@"senderName"];
        _contactId = dict[@"contact_id"] ?: dict[@"contactId"];

        id timestamp = dict[@"timestamp"];
        if ([timestamp isKindOfClass:[NSNumber class]]) {
            _originalTime = [NSDate dateWithTimeIntervalSince1970:[timestamp doubleValue]];
        } else if ([timestamp isKindOfClass:[NSDate class]]) {
            _originalTime = timestamp;
        }

        _revokeTime = [NSDate date];
        _messageType = [dict[@"messageType"] integerValue];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"messageId": self.messageId ?: @"",
        @"content": self.content ?: @"",
        @"senderName": self.senderName ?: @"",
        @"contactId": self.contactId ?: @"",
        @"originalTime": @([self.originalTime timeIntervalSince1970]),
        @"revokeTime": @([self.revokeTime timeIntervalSince1970]),
        @"messageType": @(self.messageType)
    };
}

- (NSString *)formattedDescription {
    NSString *sender = self.senderName ?: @"未知";
    NSString *body = self.content ?: @"[非文本消息]";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"MM-dd HH:mm:ss";
    NSString *timeStr = [fmt stringFromDate:self.originalTime ?: self.revokeTime];
    return [NSString stringWithFormat:@"[%@] %@: %@ (已撤回)", timeStr, sender, body];
}

@end
