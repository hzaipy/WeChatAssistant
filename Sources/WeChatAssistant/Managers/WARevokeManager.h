//
//  WARevokeManager.h
//  WeChatAssistant
//
//  撤回消息管理器 - 存储和查询被撤回的消息
//

#import <Foundation/Foundation.h>

@interface WARevokeManager : NSObject

+ (instancetype)sharedManager;

/// 初始化数据库
- (void)setupDatabase;

/// 记录被撤回的消息
- (void)recordRevokedMessage:(NSString *)content
                      sender:(NSString *)sender
                      msgId:(NSString *)msgId
                  timestamp:(NSDate *)timestamp;

/// 查询所有被撤回的消息
- (NSArray<NSDictionary *> *)allRevokedMessages;

/// 按群聊/联系人过滤
- (NSArray<NSDictionary *> *)revokedMessagesForContact:(NSString *)contactId;

/// 最近的撤回消息（限制数量）
- (NSArray<NSDictionary *> *)recentRevokedMessages:(NSUInteger)limit;

/// 清空记录
- (void)clearAllRecords;

@end
