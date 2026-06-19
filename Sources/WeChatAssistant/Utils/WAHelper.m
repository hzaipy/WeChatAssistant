//
//  WAHelper.m
//  WeChatAssistant
//

#import "WAHelper.h"
#import "WALogger.h"
#import <sys/sysctl.h>

@implementation WAHelper

+ (NSString *)wechatVersion {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    return version ?: @"unknown";
}

+ (NSString *)wechatDataDirectory {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@"Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat"];
}

+ (BOOL)isAppleSilicon {
    int mib[] = { CTL_HW, HW_MACHINE };
    size_t len = 0;
    sysctl(mib, 2, NULL, &len, NULL, 0);
    char *machine = malloc(len);
    sysctl(mib, 2, machine, &len, NULL, 0);
    NSString *model = [NSString stringWithUTF8String:machine];
    free(machine);

    // M 芯片型号以 "arm64" 开头或包含特定标识
    return [model hasPrefix:@"arm64"] || [model containsString:@"Mac"];
}

+ (id)safePerformSelector:(SEL)selector onObject:(id)object {
    if (!object || !selector) return nil;
    if (![object respondsToSelector:selector]) {
        WALogWarn(@"对象 %@ 不响应 %@", [object class], NSStringFromSelector(selector));
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

@end
