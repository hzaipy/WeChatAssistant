//
//  WARevokeHistoryController.m
//  WeChatAssistant
//

#import "WARevokeHistoryController.h"
#import "WARevokeManager.h"
#import "WALogger.h"

@interface WARevokeHistoryController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *messages;
@end

@implementation WARevokeHistoryController

+ (instancetype)sharedController {
    static WARevokeHistoryController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WARevokeHistoryController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = @"撤回消息历史";
        [window center];
        [self setupUI];
        [self refreshData];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;

    // 工具栏
    NSView *toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, 360, 600, 40)];

    NSButton *refreshBtn = [[NSButton alloc] initWithFrame:NSMakeRect(10, 5, 80, 28)];
    refreshBtn.title = @"刷新";
    refreshBtn.bezelStyle = NSBezelStyleRounded;
    refreshBtn.target = self;
    refreshBtn.action = @selector(refreshData);
    [toolbar addSubview:refreshBtn];

    NSButton *clearBtn = [[NSButton alloc] initWithFrame:NSMakeRect(100, 5, 80, 28)];
    clearBtn.title = @"清空";
    clearBtn.bezelStyle = NSBezelStyleRounded;
    clearBtn.target = self;
    clearBtn.action = @selector(clearHistory);
    [toolbar addSubview:clearBtn];

    [contentView addSubview:toolbar];

    // 表格
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 360)];
    scrollView.hasVerticalScroller = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;

    // 列
    NSTableColumn *timeCol = [[NSTableColumn alloc] initWithIdentifier:@"time"];
    timeCol.title = @"时间";
    timeCol.width = 120;
    [self.tableView addTableColumn:timeCol];

    NSTableColumn *senderCol = [[NSTableColumn alloc] initWithIdentifier:@"sender"];
    senderCol.title = @"发送者";
    senderCol.width = 100;
    [self.tableView addTableColumn:senderCol];

    NSTableColumn *contentCol = [[NSTableColumn alloc] initWithIdentifier:@"content"];
    contentCol.title = @"消息内容";
    contentCol.width = 360;
    [self.tableView addTableColumn:contentCol];

    scrollView.documentView = self.tableView;
    [contentView addSubview:scrollView];
}

- (void)refreshData {
    self.messages = [[WARevokeManager sharedManager] allRevokedMessages];
    [self.tableView reloadData];
    WALogInfo(@"撤回历史已刷新: %lu 条记录", (unsigned long)self.messages.count);
}

- (void)clearHistory {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"确认清空";
    alert.informativeText = @"确定要清空所有撤回消息历史记录吗？此操作不可撤销。";
    [alert addButtonWithTitle:@"清空"];
    [alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            [[WARevokeManager sharedManager] clearAllRecords];
            [self refreshData];
        }
    }];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.messages.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row >= self.messages.count) return nil;

    NSDictionary *msg = self.messages[row];
    NSString *colId = tableColumn.identifier;

    if ([colId isEqualToString:@"time"]) {
        double ts = [msg[@"timestamp"] doubleValue];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd HH:mm:ss";
        return [fmt stringFromDate:date];
    } else if ([colId isEqualToString:@"sender"]) {
        return msg[@"sender"] ?: @"未知";
    } else if ([colId isEqualToString:@"content"]) {
        return msg[@"content"] ?: @"[非文本消息]";
    }
    return nil;
}

- (void)showWindow {
    [self.window makeKeyAndOrderFront:nil];
    [self refreshData];
}

@end
