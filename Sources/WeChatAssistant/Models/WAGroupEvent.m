//
//  WAGroupEvent.m
//  WeChatAssistant
//

#import "WAGroupEvent.h"

@implementation WAGroupEvent

- (instancetype)init {
    self = [super init];
    if (self) {
        _timestamp = [NSDate date];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _eventType = [dict[@"change_type"] integerValue];
        _groupName = dict[@"group_name"];
        _memberName = dict[@"member_name"];
        _eventDescription = dict[@"event_type"];

        id ts = dict[@"timestamp"];
        if ([ts isKindOfClass:[NSNumber class]]) {
            _timestamp = [NSDate dateWithTimeIntervalSince1970:[ts doubleValue]];
        }
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"eventType": @(self.eventType),
        @"groupName": self.groupName ?: @"",
        @"memberName": self.memberName ?: @"",
        @"timestamp": @([self.timestamp timeIntervalSince1970]),
        @"eventDescription": self.eventDescription ?: @""
    };
}

- (NSString *)formattedDescription {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"MM-dd HH:mm:ss";
    NSString *timeStr = [fmt stringFromDate:self.timestamp];
    NSString *desc = self.eventDescription ?: [self eventTypeString];
    return [NSString stringWithFormat:@"[%@] %@ | %@ | %@",
            timeStr, self.groupName ?: @"未知群", desc, self.memberName ?: @""];
}

- (NSString *)eventTypeString {
    switch (self.eventType) {
        case WAGroupEventTypeMemberJoin:   return @"成员加入";
        case WAGroupEventTypeMemberLeave:  return @"成员退出";
        case WAGroupEventTypeMemberKicked: return @"被移出群聊";
        case WAGroupEventTypeNameChanged:  return @"群名变更";
        case WAGroupEventTypeAnnouncement: return @"群公告";
        default: return @"未知事件";
    }
}

@end
