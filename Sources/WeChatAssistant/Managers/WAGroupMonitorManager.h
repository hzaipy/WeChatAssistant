//
//  WAGroupMonitorManager.h
//  WeChatAssistant
//

#import <Foundation/Foundation.h>

@interface WAGroupMonitorManager : NSObject

+ (instancetype)sharedManager;

/// 开始监控
- (void)startMonitoring;

/// 停止监控
- (void)stopMonitoring;

/// 记录群事件
- (void)recordGroupEvent:(NSString *)eventType
               groupName:(NSString *)groupName
              memberName:(NSString *)memberName
              changeType:(NSInteger)changeType;

/// 查询群事件历史
- (NSArray<NSDictionary *> *)allGroupEvents;
- (NSArray<NSDictionary *> *)recentGroupEvents:(NSUInteger)limit;

/// 清空记录
- (void)clearAllRecords;

@end
