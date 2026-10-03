#import <AppKit/AppKit.h>

@interface DragProbeView : NSView <NSDraggingDestination>
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *logTextView;
@end

@implementation DragProbeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        NSArray *dragTypes = @[
            NSPasteboardTypeURL,
            NSPasteboardTypeString,
            NSPasteboardTypeFileURL,
            (NSString *)kUTTypeURL,
            (NSString *)kUTTypePlainText,
            @"public.url",
            @"public.utf8-plain-text",
            @"WebURLsWithTitlesPboardType",
            @"text/uri-list",
            @"NSURLPboardType",
            @"NSFilenamesPboardType"
        ];
        [self registerForDraggedTypes:dragTypes];
        
        // Setup visual elements
        _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, frameRect.size.height - 80, frameRect.size.width - 40, 50)];
        [_statusLabel setEditable:NO];
        [_statusLabel setSelectable:NO];
        [_statusLabel setBezeled:NO];
        [_statusLabel setDrawsBackground:YES];
        [_statusLabel setBackgroundColor:[NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.18 alpha:1.0]];
        [_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.3 green:0.9 blue:0.4 alpha:1.0]];
        [_statusLabel setFont:[NSFont boldSystemFontOfSize:18]];
        [_statusLabel setAlignment:NSTextAlignmentCenter];
        [_statusLabel setStringValue:@"READY FOR DRAG (Safari / Chrome / Finder)"];
        [self addSubview:_statusLabel];
        
        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, frameRect.size.width - 40, frameRect.size.height - 110)];
        [scrollView setHasVerticalScroller:YES];
        [scrollView setHasHorizontalScroller:YES];
        [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        _logTextView = [[NSTextView alloc] initWithFrame:scrollView.contentView.bounds];
        [_logTextView setEditable:NO];
        [_logTextView setSelectable:YES];
        [_logTextView setFont:[NSFont userFixedPitchFontOfSize:13]];
        [_logTextView setBackgroundColor:[NSColor colorWithCalibratedRed:0.05 green:0.05 blue:0.08 alpha:1.0]];
        [_logTextView setTextColor:[NSColor colorWithCalibratedRed:0.9 green:0.9 blue:0.9 alpha:1.0]];
        [scrollView setDocumentView:_logTextView];
        [self addSubview:scrollView];
        
        [self log:@"=================================================="];
        [self log:@"StudyCenterHub Native macOS Drag & Drop Probe v1.0"];
        [self log:@"Registered Pasteboard Types:"];
        for (NSString *t in dragTypes) {
            [self log:[NSString stringWithFormat:@"  - %@", t]];
        }
        [self log:@"=================================================="];
        [self log:@"Drag any YouTube link, thumbnail, tab, or file here..."];
    }
    return self;
}

- (void)log:(NSString *)msg {
    NSString *line = [NSString stringWithFormat:@"%@\n", msg];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_logTextView setString:[self->_logTextView.string stringByAppendingString:line]];
        [self->_logTextView scrollRangeToVisible:NSMakeRange(self->_logTextView.string.length, 0)];
        NSLog(@"[PROBE_LOG] %@", msg);
    });
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSArray *types = [pboard types];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_statusLabel setStringValue:@"🟢 DRAG ENTERED NATIVE PROBE VIEW!"];
        [self->_statusLabel setBackgroundColor:[NSColor colorWithCalibratedRed:0.0 green:0.4 blue:0.1 alpha:1.0]];
    });
    
    [self log:@"\n--------------------------------------------------"];
    [self log:[NSString stringWithFormat:@"[EVENT] draggingEntered: from source %@", [sender draggingSource]]];
    [self log:[NSString stringWithFormat:@"[PASTEBOARD TYPES OFFERED (%lu)]:", (unsigned long)types.count]];
    for (NSString *type in types) {
        [self log:[NSString stringWithFormat:@"  • %@", type]];
    }
    
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_statusLabel setStringValue:@"READY FOR DRAG (Safari / Chrome / Finder)"];
        [self->_statusLabel setBackgroundColor:[NSColor colorWithCalibratedRed:0.1 green:0.1 blue:0.18 alpha:1.0]];
    });
    [self log:@"[EVENT] draggingExited"];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSArray *types = [pboard types];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_statusLabel setStringValue:@"🎉 DROP RECEIVED SUCCESSFULLY!"];
        [self->_statusLabel setBackgroundColor:[NSColor colorWithCalibratedRed:0.1 green:0.5 blue:0.9 alpha:1.0]];
    });
    
    [self log:@"\n=================================================="];
    [self log:@"[EVENT] performDragOperation: EXPORTING PAYLOAD CONTENT:"];
    
    // Check all common URL/Text representations
    for (NSString *type in types) {
        NSString *str = [pboard stringForType:type];
        if (str) {
            if (str.length > 200) {
                str = [[str substringToIndex:200] stringByAppendingString:@"... (truncated)"];
            }
            [self log:[NSString stringWithFormat:@"  Type '%@' => '%@'", type, str]];
        } else {
            id propList = [pboard propertyListForType:type];
            if (propList) {
                [self log:[NSString stringWithFormat:@"  Type '%@' (PropertyList) => %@", type, propList]];
            }
        }
    }
    
    // NSURL extraction
    NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
    if (urls && urls.count > 0) {
        [self log:@"[EXTRACTED NSURL OBJECTS]:"];
        for (NSURL *url in urls) {
            [self log:[NSString stringWithFormat:@"  -> %@", url.absoluteString]];
        }
    }
    
    [self log:@"==================================================\n"];
    return YES;
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSRect frame = NSMakeRect(200, 200, 720, 500);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"StudyCenterHub - Native macOS Drag & Drop Probe"];
    
    DragProbeView *probeView = [[DragProbeView alloc] initWithFrame:[[_window contentView] bounds]];
    [probeView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[_window contentView] addSubview:probeView];
    
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
