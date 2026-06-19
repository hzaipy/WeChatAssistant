//
//  WAGroupMonitorManager.m
//  WeChatAssistant
//

#import "WAGroupMonitorManager.h"
#import "WALogger.h"
#import <sqlite3.h>
#import <UserNotifications/UserNotifications.h>

@interface WAGroupMonitorManager ()
@property (nonatomic, assign) sqlite3 *database;
@property (nonatomic, strong) dispatch_queue_t dbQueue;
@property (nonatomic, assign) BOOL isMonitoring;
@end

@implementation WAGroupMonitorManager

+ (instancetype)sharedManager {
    static WAGroupMonitorManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WAGroupMonitorManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dbQueue = dispatch_queue_create("com.wechatassistant.group.db", DISPATCH_QUEUE_SERIAL);
        _isMonitoring = NO;
    }
    return self;
}

- (NSString *)databasePath {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [appSupport stringByAppendingPathComponent:@"WeChatAssistant/Data"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [dir stringByAppendingPathComponent:@"group_events.db"];
}

- (void)startMonitoring {
    if (self.isMonitoring) return;
    self.isMonitoring = YES;

    dispatch_async(self.dbQueue, ^{
        NSString *dbPath = [self databasePath];
        int rc = sqlite3_open([dbPath UTF8String], &self->_database);
        if (rc != SQLITE_OK) {
            WALogError(@"群事件数据库打开失败: %s", sqlite3_errmsg(self->_database));
            return;
        }

        const char *sql = "CREATE TABLE IF NOT EXISTS group_events ("
                          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                          "event_type TEXT,"
                          "group_name TEXT,"
                          "member_name TEXT,"
                          "change_type INTEGER,"
                          "timestamp REAL,"
                          "created_at REAL DEFAULT (strftime('%s','now'))"
                          ");";

        char *errMsg = NULL;
        rc = sqlite3_exec(self->_database, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            WALogError(@"创建群事件表失败: %s", errMsg);
            sqlite3_free(errMsg);
        } else {
            WALogInfo(@"群事件数据库就绪: %@", dbPath);
        }
    });

    // 请求通知权限
    if (@available(macOS 11.0, *)) {
        [[UNUserNotificationCenter currentNotificationCenter]
         requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
         completionHandler:^(BOOL granted, NSError *error) {
            if (granted) {
                WALogInfo(@"通知权限已获取");
            } else {
                WALogWarn(@"通知权限被拒绝: %@", error);
            }
        }];
    }

    WALogInfo(@"退群监控已启动");
}

- (void)stopMonitoring {
    self.isMonitoring = NO;
    WALogInfo(@"退群监控已停止");
}

- (void)recordGroupEvent:(NSString *)eventType
               groupName:(NSString *)groupName
              memberName:(NSString *)memberName
              changeType:(NSInteger)changeType {

    // 存储到数据库
    dispatch_async(self.dbQueue, ^{
        const char *sql = "INSERT INTO group_events (event_type, group_name, member_name, change_type, timestamp) VALUES (?, ?, ?, ?, ?);";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(self->_database, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, [eventType UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [groupName UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [memberName UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 4, (sqlite3_int64)changeType);
        sqlite3_bind_double(stmt, 5, [[NSDate date] timeIntervalSince1970]);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    });

    // 发送系统通知
    [self sendNotification:eventType groupName:groupName memberName:memberName];
}

- (void)sendNotification:(NSString *)eventType
               groupName:(NSString *)groupName
              memberName:(NSString *)memberName {

    if (@available(macOS 11.0, *)) {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = [NSString stringWithFormat:@"👥 %@", eventType];
        content.body = [NSString stringWithFormat:@"%@ 在群「%@」%@",
                        memberName ?: @"有人", groupName ?: @"未知群聊", eventType];
        content.sound = [UNNotificationSound defaultSound];

        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:
            [NSString stringWithFormat:@"group-event-%f", [[NSDate date] timeIntervalSince1970]]
            content:content trigger:nil];

        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
            withCompletionHandler:^(NSError *error) {
            if (error) {
                WALogWarn(@"发送通知失败: %@", error);
            }
        }];
    } else {
        // macOS 10.x fallback: NSUserNotification
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        notification.title = [NSString stringWithFormat:@"👥 %@", eventType];
        notification.informativeText = [NSString stringWithFormat:@"%@ 在群「%@」%@",
                                         memberName ?: @"有人", groupName ?: @"未知群聊", eventType];
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
        #pragma clang diagnostic pop
    }
}

- (NSArray<NSDictionary *> *)allGroupEvents {
    return [self queryEvents:@"SELECT * FROM group_events ORDER BY timestamp DESC;"];
}

- (NSArray<NSDictionary *> *)recentGroupEvents:(NSUInteger)limit {
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM group_events ORDER BY timestamp DESC LIMIT %lu;", (unsigned long)limit];
    return [self queryEvents:sql];
}

- (void)clearAllRecords {
    dispatch_async(self.dbQueue, ^{
        sqlite3_exec(self->_database, "DELETE FROM group_events;", NULL, NULL, NULL);
        WALogInfo(@"已清空所有群事件记录");
    });
}

- (NSArray<NSDictionary *> *)queryEvents:(NSString *)sql {
    __block NSMutableArray *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(self->_database, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) return;

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            int colCount = sqlite3_column_count(stmt);
            for (int i = 0; i < colCount; i++) {
                NSString *colName = [NSString stringWithUTF8String:sqlite3_column_name(stmt, i)];
                const char *text = (const char *)sqlite3_column_text(stmt, i);
                row[colName] = text ? [NSString stringWithUTF8String:text] : @(sqlite3_column_double(stmt, i));
            }
            [results addObject:row];
        }
        sqlite3_finalize(stmt);
    });
    return results;
}

- (void)dealloc {
    if (_database) sqlite3_close(_database);
}

@end
