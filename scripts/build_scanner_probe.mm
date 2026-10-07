#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

@interface ScannerProbeAppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextField *textField;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSTextField *statsLabel;
@property (nonatomic, assign) NSUInteger keyCount;
@property (nonatomic, assign) NSUInteger textChangeCount;
@end

@implementation ScannerProbeAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect frame = NSMakeRect(200, 200, 700, 520);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    
    _window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    [_window setTitle:@"🔍 StudyCenterHub Physical Scanner Native Probe (AppKit Diagnostic)"];
    [_window setBackgroundColor:[NSColor colorWithCalibratedRed:0.08 green:0.11 blue:0.18 alpha:1.0]];
    
    NSView *contentView = [_window contentView];
    
    // 1. Header Label
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 460, 660, 40)];
    [header setEditable:NO];
    [header setSelectable:NO];
    [header setBezeled:NO];
    [header setDrawsBackground:NO];
    [header setTextColor:[NSColor colorWithCalibratedRed:1.0 green:0.82 blue:0.3 alpha:1.0]];
    [header setFont:[NSFont boldSystemFontOfSize:15]];
    [header setStringValue:@"PHYSICAL SCANNER DIAGNOSTIC PROBE — Native Cocoa Text Field Test"];
    [contentView addSubview:header];
    
    // 2. Instructions Label
    NSTextField *instr = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 425, 660, 30)];
    [instr setEditable:NO];
    [instr setSelectable:NO];
    [instr setBezeled:NO];
    [instr setDrawsBackground:NO];
    [instr setTextColor:[NSColor colorWithCalibratedRed:0.75 green:0.82 blue:0.92 alpha:1.0]];
    [instr setFont:[NSFont systemFontOfSize:12]];
    [instr setStringValue:@"Pull the physical scanner trigger ONCE while focused in the text box below."];
    [contentView addSubview:instr];
    
    // 3. Standard Native NSTextField
    _textField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 375, 660, 42)];
    [_textField setFont:[NSFont fontWithName:@"Menlo" size:16] ?: [NSFont userFixedPitchFontOfSize:16]];
    [_textField setPlaceholderString:@"Scanner input target field — Pull scanner trigger here..."];
    [_textField setDelegate:self];
    [contentView addSubview:_textField];
    
    // 4. Live Stats Counter Label
    _statsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 335, 660, 32)];
    [_statsLabel setEditable:NO];
    [_statsLabel setSelectable:NO];
    [_statsLabel setBezeled:NO];
    [_statsLabel setDrawsBackground:YES];
    [_statsLabel setBackgroundColor:[NSColor colorWithCalibratedRed:0.12 green:0.16 blue:0.25 alpha:1.0]];
    [_statsLabel setTextColor:[NSColor colorWithCalibratedRed:0.30 green:0.90 blue:1.0 alpha:1.0]];
    [_statsLabel setFont:[NSFont boldSystemFontOfSize:13]];
    [_statsLabel setAlignment:NSTextAlignmentCenter];
    [_statsLabel setStringValue:@"AppKit KeyDown Events: 0 | Text Changes: 0 | Last KeyCode: None"];
    [contentView addSubview:_statsLabel];
    
    // 5. Scrollable Event Log Area
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 660, 300)];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasHorizontalScroller:NO];
    [scroll setAutohidesScrollers:YES];
    
    _logTextView = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    [_logTextView setEditable:NO];
    [_logTextView setSelectable:YES];
    [_logTextView setBackgroundColor:[NSColor colorWithCalibratedRed:0.04 green:0.06 blue:0.10 alpha:1.0]];
    [_logTextView setTextColor:[NSColor colorWithCalibratedRed:0.85 green:0.92 blue:1.0 alpha:1.0]];
    [_logTextView setFont:[NSFont fontWithName:@"Menlo" size:12] ?: [NSFont userFixedPitchFontOfSize:12]];
    [scroll setDocumentView:_logTextView];
    [contentView addSubview:scroll];
    
    [self appendLog:@"[PROBE_STARTED] Native AppKit Diagnostic Probe Initialized."];
    [self appendLog:@"[PROBE_READY] Focus set to native Cocoa NSTextField."];
    
    // Install PASSIVE local NSEvent monitors for multiple event types
    NSEventMask mask = NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged | NSEventMaskSystemDefined | NSEventMaskApplicationDefined;
    [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) {
        if (!event) return event;
        
        NSString *typeStr = @"OTHER";
        switch (event.type) {
            case NSEventTypeKeyDown:
                self.keyCount++;
                typeStr = @"KeyDown";
                break;
            case NSEventTypeKeyUp:
                typeStr = @"KeyUp";
                break;
            case NSEventTypeFlagsChanged:
                typeStr = @"FlagsChanged";
                break;
            case NSEventTypeSystemDefined:
                typeStr = @"SystemDefined";
                break;
            case NSEventTypeApplicationDefined:
                typeStr = @"AppDefined";
                break;
            default:
                break;
        }
        
        NSString *chars = (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp) ? [event characters] : @"";
        NSString *charsEsc = [chars stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
        charsEsc = [charsEsc stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        
        [self appendLog:[NSString stringWithFormat:@"[NSEVENT] %s | keyCode=%d | chars='%@' (len=%lu) | flags=0x%lx | win=%@",
                         [typeStr UTF8String], (int)event.keyCode, charsEsc, (unsigned long)chars.length, (unsigned long)event.modifierFlags,
                         event.window ? [event.window className] : @"nil"]];
        
        [self updateStatsLabel:event.keyCode];
        return event; // PASSIVE RETURN
    }];
    
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_textField];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    _textChangeCount++;
    NSString *val = [_textField stringValue];
    NSString *valEsc = [val stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    valEsc = [valEsc stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    
    [self appendLog:[NSString stringWithFormat:@"[NSTEXTFIELD_CHANGED] Text length=%lu | value='%@'",
                     (unsigned long)val.length, valEsc]];
    [self updateStatsLabel:-1];
}

- (void)appendLog:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", ts, msg];
        
        NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:line attributes:@{
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.4 green:0.9 blue:0.6 alpha:1.0],
            NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont userFixedPitchFontOfSize:12]
        }];
        [[self->_logTextView textStorage] appendAttributedString:attrStr];
        [self->_logTextView scrollRangeToVisible:NSMakeRange([[self->_logTextView string] length], 0)];
    });
}

- (void)updateStatsLabel:(NSInteger)keyCode {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *kcStr = (keyCode >= 0) ? [NSString stringWithFormat:@"%ld", (long)keyCode] : @"None";
        [self->_statsLabel setStringValue:[NSString stringWithFormat:@"AppKit KeyDown Events: %lu | Text Changes: %lu | Last KeyCode: %@",
                                            (unsigned long)self.keyCount, (unsigned long)self.textChangeCount, kcStr]];
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ScannerProbeAppDelegate *delegate = [[ScannerProbeAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
