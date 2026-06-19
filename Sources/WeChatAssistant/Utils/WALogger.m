//
//  WALogger.m
//  WeChatAssistant
//

#import "WALogger.h"

static WALogLevel gMinLevel = WALogLevelDebug;
static NSFileHandle *gLogFileHandle = nil;
static dispatch_queue_t gLogQueue = nil;

@implementation WALogger

+ (void)initialize {
    if (self == [WALogger class]) {
        gLogQueue = dispatch_queue_create("com.wechatassistant.logger", DISPATCH_QUEUE_SERIAL);
        [self setupLogFile];
    }
}

+ (void)setupLogFile {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                          NSUserDomainMask, YES) firstObject];
    NSString *logDir = [dir stringByAppendingPathComponent:@"WeChatAssistant/Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *path = [logDir stringByAppendingPathComponent:@"wechat-assistant.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    }
    gLogFileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    [gLogFileHandle seekToEndOfFile];
}

+ (NSString *)logFilePath {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                          NSUserDomainMask, YES) firstObject];
    return [[dir stringByAppendingPathComponent:@"WeChatAssistant/Logs"]
            stringByAppendingPathComponent:@"wechat-assistant.log"];
}

+ (void)log:(WALogLevel)level file:(const char *)file line:(int)line format:(NSString *)format, ... {
    if (level < gMinLevel) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *levelStr;
    switch (level) {
        case WALogLevelDebug: levelStr = @"DEBUG"; break;
        case WALogLevelInfo:  levelStr = @"INFO";  break;
        case WALogLevelWarn:  levelStr = @"WARN";  break;
        case WALogLevelError: levelStr = @"ERROR"; break;
    }

    NSString *fileName = [[NSString stringWithUTF8String:file] lastPathComponent];
    NSString *lineStr = [NSString stringWithFormat:@"[%@] [%@:%d] %@", levelStr, fileName, line, message];

    NSLog(@"[WeChatAssistant] %@", lineStr);

    dispatch_async(gLogQueue, ^{
        NSString *entry = [NSString stringWithFormat:@"%@ %@\n",
                           [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                          dateStyle:NSDateFormatterShortStyle
                                                          timeStyle:NSDateFormatterMediumStyle],
                           lineStr];
        [gLogFileHandle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
    });
}

+ (void)setMinimumLevel:(WALogLevel)level {
    gMinLevel = level;
}

@end
