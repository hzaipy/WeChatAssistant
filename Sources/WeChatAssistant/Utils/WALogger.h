//
//  WALogger.h
//  WeChatAssistant
//
//  统一日志工具 - 输出到 NSLog 和本地文件
//

#import <Foundation/Foundation.h>

#define WALogDebug(fmt, ...) [WALogger log:WALogLevelDebug file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]
#define WALogInfo(fmt, ...)  [WALogger log:WALogLevelInfo  file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]
#define WALogWarn(fmt, ...)  [WALogger log:WALogLevelWarn  file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]
#define WALogError(fmt, ...) [WALogger log:WALogLevelError file:__FILE__ line:__LINE__ format:fmt, ##__VA_ARGS__]

typedef NS_ENUM(NSInteger, WALogLevel) {
    WALogLevelDebug = 0,
    WALogLevelInfo,
    WALogLevelWarn,
    WALogLevelError
};

@interface WALogger : NSObject

+ (void)log:(WALogLevel)level file:(const char *)file line:(int)line format:(NSString *)format, ...;
+ (void)setMinimumLevel:(WALogLevel)level;
+ (NSString *)logFilePath;

@end
