//
//  WARevokeManager.m
//  WeChatAssistant
//
//  使用 SQLite 存储撤回消息记录
//

#import "WARevokeManager.h"
#import "WALogger.h"
#import <sqlite3.h>

@interface WARevokeManager ()
@property (nonatomic, assign) sqlite3 *database;
@property (nonatomic, strong) dispatch_queue_t dbQueue;
@end

@implementation WARevokeManager

+ (instancetype)sharedManager {
    static WARevokeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WARevokeManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dbQueue = dispatch_queue_create("com.wechatassistant.revoke.db", DISPATCH_QUEUE_SERIAL);
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
    return [dir stringByAppendingPathComponent:@"revoked_messages.db"];
}

- (void)setupDatabase {
    dispatch_async(self.dbQueue, ^{
        NSString *dbPath = [self databasePath];
        int rc = sqlite3_open([dbPath UTF8String], &self->_database);
        if (rc != SQLITE_OK) {
            WALogError(@"无法打开数据库: %s", sqlite3_errmsg(self->_database));
            return;
        }

        const char *sql = "CREATE TABLE IF NOT EXISTS revoked_messages ("
                          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                          "msg_id TEXT,"
                          "content TEXT,"
                          "sender TEXT,"
                          "contact_id TEXT,"
                          "timestamp REAL,"
                          "created_at REAL DEFAULT (strftime('%s','now'))"
                          ");";

        char *errMsg = NULL;
        rc = sqlite3_exec(self->_database, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            WALogError(@"创建表失败: %s", errMsg);
            sqlite3_free(errMsg);
        } else {
            WALogInfo(@"撤回消息数据库就绪: %@", dbPath);
        }
    });
}

- (void)recordRevokedMessage:(NSString *)content
                      sender:(NSString *)sender
                      msgId:(NSString *)msgId
                  timestamp:(NSDate *)timestamp {

    dispatch_async(self.dbQueue, ^{
        const char *sql = "INSERT INTO revoked_messages (msg_id, content, sender, timestamp) VALUES (?, ?, ?, ?);";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(self->_database, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            WALogError(@"准备插入语句失败: %s", sqlite3_errmsg(self->_database));
            return;
        }

        sqlite3_bind_text(stmt, 1, [msgId UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [content UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [sender UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, [timestamp timeIntervalSince1970]);

        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            WALogError(@"插入撤回消息失败: %s", sqlite3_errmsg(self->_database));
        }
        sqlite3_finalize(stmt);

        WALogInfo(@"📝 已记录撤回消息: [%@] %@", sender ?: @"未知", content ?: @"(无文本)");
    });
}

- (NSArray<NSDictionary *> *)allRevokedMessages {
    return [self queryMessages:@"SELECT * FROM revoked_messages ORDER BY timestamp DESC;"];
}

- (NSArray<NSDictionary *> *)revokedMessagesForContact:(NSString *)contactId {
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM revoked_messages WHERE contact_id = '%@' ORDER BY timestamp DESC;", contactId];
    return [self queryMessages:sql];
}

- (NSArray<NSDictionary *> *)recentRevokedMessages:(NSUInteger)limit {
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM revoked_messages ORDER BY timestamp DESC LIMIT %lu;", (unsigned long)limit];
    return [self queryMessages:sql];
}

- (void)clearAllRecords {
    dispatch_async(self.dbQueue, ^{
        const char *sql = "DELETE FROM revoked_messages;";
        char *errMsg = NULL;
        int rc = sqlite3_exec(self->_database, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            WALogError(@"清空记录失败: %s", errMsg);
            sqlite3_free(errMsg);
        } else {
            WALogInfo(@"已清空所有撤回消息记录");
        }
    });
}

- (NSArray<NSDictionary *> *)queryMessages:(NSString *)sql {
    __block NSMutableArray *results = [NSMutableArray array];
    dispatch_sync(self.dbQueue, ^{
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(self->_database, [sql UTF8String], -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            WALogError(@"查询失败: %s", sqlite3_errmsg(self->_database));
            return;
        }

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            int colCount = sqlite3_column_count(stmt);
            for (int i = 0; i < colCount; i++) {
                NSString *colName = [NSString stringWithUTF8String:sqlite3_column_name(stmt, i)];
                const char *text = (const char *)sqlite3_column_text(stmt, i);
                if (text) {
                    row[colName] = [NSString stringWithUTF8String:text];
                } else {
                    double dval = sqlite3_column_double(stmt, i);
                    row[colName] = @(dval);
                }
            }
            [results addObject:row];
        }
        sqlite3_finalize(stmt);
    });
    return results;
}

- (void)dealloc {
    if (_database) {
        sqlite3_close(_database);
    }
}

@end
