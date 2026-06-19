//
//  WAGroupEvent.h
//  WeChatAssistant
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WAGroupEventType) {
    WAGroupEventTypeMemberJoin = 0,
    WAGroupEventTypeMemberLeave,
    WAGroupEventTypeMemberKicked,
    WAGroupEventTypeNameChanged,
    WAGroupEventTypeAnnouncement
};

@interface WAGroupEvent : NSObject

@property (nonatomic, assign) WAGroupEventType eventType;
@property (nonatomic, copy) NSString *groupName;
@property (nonatomic, copy) NSString *groupID;
@property (nonatomic, copy) NSString *memberName;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, copy) NSString *eventDescription;

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
- (NSString *)formattedDescription;

@end
