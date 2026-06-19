//
//  WARevokeBubble.m
//  WeChatAssistant
//

#import "WARevokeBubble.h"

@interface WARevokeBubble ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *contentLabel;
@property (nonatomic, strong) NSTextField *timeLabel;
@end

@implementation WARevokeBubble

- (instancetype)initWithSenderName:(NSString *)senderName
                           content:(NSString *)content
                         timestamp:(NSDate *)timestamp {
    self = [super initWithFrame:NSMakeRect(0, 0, 280, 60)];
    if (self) {
        _senderName = senderName;
        _content = content;
        _timestamp = timestamp;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.wantsLayer = YES;
    self.layer.backgroundColor = [[NSColor colorWithRed:1.0 green:0.9 blue:0.8 alpha:1.0] CGColor];
    self.layer.cornerRadius = 8;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [[NSColor colorWithRed:1.0 green:0.7 blue:0.4 alpha:1.0] CGColor];

    // 标题: "xxx 撤回了一条消息"
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 34, 256, 18)];
    self.titleLabel.stringValue = [NSString stringWithFormat:@"%@ 撤回了一条消息", self.senderName ?: @"对方"];
    self.titleLabel.font = [NSFont boldSystemFontOfSize:12];
    self.titleLabel.textColor = [NSColor colorWithRed:0.8 green:0.4 blue:0.1 alpha:1.0];
    self.titleLabel.backgroundColor = [NSColor clearColor];
    self.titleLabel.bordered = NO;
    self.titleLabel.editable = NO;
    [self addSubview:self.titleLabel];

    // 内容预览
    self.contentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 16, 256, 16)];
    NSString *preview = self.content;
    if (preview.length > 40) {
        preview = [[preview substringToIndex:40] stringByAppendingString:@"..."];
    }
    self.contentLabel.stringValue = preview ?: @"[非文本消息]";
    self.contentLabel.font = [NSFont systemFontOfSize:11];
    self.contentLabel.textColor = [NSColor grayColor];
    self.contentLabel.backgroundColor = [NSColor clearColor];
    self.contentLabel.bordered = NO;
    self.contentLabel.editable = NO;
    [self addSubview:self.contentLabel];

    // 时间
    self.timeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 0, 256, 14)];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    self.timeLabel.stringValue = [fmt stringFromDate:self.timestamp ?: [NSDate date]];
    self.timeLabel.font = [NSFont systemFontOfSize:10];
    self.timeLabel.textColor = [NSColor lightGrayColor];
    self.timeLabel.backgroundColor = [NSColor clearColor];
    self.timeLabel.bordered = NO;
    self.timeLabel.editable = NO;
    [self addSubview:self.timeLabel];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // 绘制左侧小图标
    NSRect iconRect = NSMakeRect(4, self.bounds.size.height - 20, 8, 8);
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:iconRect];
    [[NSColor colorWithRed:1.0 green:0.6 blue:0.2 alpha:1.0] setFill];
    [path fill];
}

@end
