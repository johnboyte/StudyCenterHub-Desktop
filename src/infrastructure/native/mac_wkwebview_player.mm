#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#include <mutex>
#include <vector>
#include <string>
#include <cstdlib>
#include <cstring>
#include "gdextension_interface.h"

// ==============================================================================
// MACOS NATIVE BROWSER URL DRAG & DROP BRIDGE
// ==============================================================================

// ==============================================================================
// MACOS NATIVE BROWSER URL DRAG & DROP BRIDGE
// ==============================================================================

#define NATIVE_DRAG_BRIDGE_VERSION_STR "v5.4.0-COMPACT-INDEPENDENT-DROP-SURFACE"

struct NativeDiagnosticsInfo {
    bool bridge_loaded;
    bool window_found;
    std::string app_ptr;
    int app_activation_policy;
    bool app_is_active;
    std::string main_window_ptr;
    std::string key_window_ptr;
    std::string independent_window_ptr;
    std::string independent_parent_ptr;
    std::string independent_window_class;
    long independent_window_level;
    unsigned long independent_style_mask;
    bool independent_is_visible;
    bool independent_ignores_mouse;
    std::string independent_content_view_class;
    std::string receiver_window_ptr;
    std::string receiver_class;
    bool receiver_attached;
    bool receiver_enabled;
    std::string frame_str;
    std::string registered_types;
};

static NativeDiagnosticsInfo g_diag_info = {
    false, false, "nil", 0, false, "nil", "nil", "nil", "nil", "None", 0, 0, false, false, "None", "nil", "None", false, false, "0,0,0,0", ""
};

struct ExternalDropEvent {
    std::string event;
    std::string raw_type;
    std::string payload;
    float x;
    float y;
    float window_w;
    float window_h;
};

static std::mutex g_drop_mutex;
static std::vector<ExternalDropEvent> g_drop_events;
static bool g_drag_bridge_initialized = false;
static void ensure_external_drag_receiver();

static void queue_external_event(const ExternalDropEvent& ev) {
    std::lock_guard<std::mutex> lock(g_drop_mutex);
    if (g_drop_events.size() > 50) {
        g_drop_events.erase(g_drop_events.begin());
    }
    g_drop_events.push_back(ev);
}

typedef NSDragOperation (*DragEnteredIMP)(id, SEL, id<NSDraggingInfo>);
typedef NSDragOperation (*DragUpdatedIMP)(id, SEL, id<NSDraggingInfo>);
typedef BOOL (*PerformDragIMP)(id, SEL, id<NSDraggingInfo>);

static IMP get_orig_imp(Class cls, SEL sel) {
    if (!cls) return NULL;
    NSString *key = [NSString stringWithFormat:@"%@_%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
    NSValue *val = objc_getAssociatedObject([NSApp class], (__bridge const void *)key);
    return val ? (IMP)[val pointerValue] : NULL;
}

static void set_orig_imp(Class cls, SEL sel, IMP imp) {
    if (!cls || !imp) return;
    NSString *key = [NSString stringWithFormat:@"%@_%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
    NSValue *val = [NSValue valueWithPointer:(const void *)imp];
    objc_setAssociatedObject([NSApp class], (__bridge const void *)key, val, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString* extractURLFromPasteboard(NSPasteboard *pboard, NSString **outType) {
    if (!pboard) return nil;
    
    // 1. Try URL objects
    NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
    if (urls && urls.count > 0) {
        for (NSURL *url in urls) {
            if (url.absoluteString && url.absoluteString.length > 0) {
                if (outType) *outType = url.isFileURL ? @"public.file-url" : @"public.url";
                return url.absoluteString;
            }
        }
    }
    
    // 2. Try NSPasteboardTypeURL
    NSString *urlStr = [pboard stringForType:NSPasteboardTypeURL];
    if (urlStr && urlStr.length > 0) {
        if (outType) *outType = @"public.url";
        return urlStr;
    }

    // 3. WebURLsWithTitlesPboardType (Safari drag)
    NSArray *webUrls = [pboard propertyListForType:@"WebURLsWithTitlesPboardType"];
    if (webUrls && [webUrls isKindOfClass:[NSArray class]] && webUrls.count > 0 && [webUrls[0] isKindOfClass:[NSArray class]]) {
        NSArray *urlList = webUrls[0];
        if (urlList.count > 0 && [urlList[0] isKindOfClass:[NSString class]]) {
            if (outType) *outType = @"WebURLsWithTitlesPboardType";
            return urlList[0];
        }
    }

    // 4. Plain text (public.utf8-plain-text / NSPasteboardTypeString)
    NSString *str = [pboard stringForType:NSPasteboardTypeString];
    if (str && str.length > 0) {
        if (outType) *outType = @"public.utf8-plain-text";
        return str;
    }

    // 5. text/uri-list
    NSString *uriList = [pboard stringForType:@"text/uri-list"];
    if (uriList && uriList.length > 0) {
        NSArray *lines = [uriList componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length > 0 && ![trimmed hasPrefix:@"#"]) {
                if (outType) *outType = @"text/uri-list";
                return trimmed;
            }
        }
    }

    // 6. File URLs / filenames (e.g. .webloc or audio/media files)
    NSArray *files = [pboard propertyListForType:NSPasteboardTypeFileURL];
    if (!files || files.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        files = [pboard propertyListForType:NSFilenamesPboardType];
#pragma clang diagnostic pop
    }
    if (files && [files isKindOfClass:[NSArray class]] && files.count > 0) {
        NSString *filePath = files[0];
        if ([filePath hasSuffix:@".webloc"]) {
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filePath];
            NSString *weblocUrl = dict[@"URL"];
            if (weblocUrl && weblocUrl.length > 0) {
                if (outType) *outType = @".webloc";
                return weblocUrl;
            }
        }
        if (outType) *outType = @"public.file-url";
        return filePath;
    }

    return nil;
}

static BOOL isSupportedDragType(NSPasteboard *pboard) {
    if (!pboard) return NO;
    NSArray *types = [pboard types];
    if (!types) return NO;
    
    NSArray *supported = @[
        NSPasteboardTypeURL,
        NSPasteboardTypeString,
        NSPasteboardTypeFileURL,
        @"public.url",
        @"public.file-url",
        @"public.utf8-plain-text",
        @"WebURLsWithTitlesPboardType",
        @"NSFilenamesPboardType",
        @"text/uri-list",
        @"public.url-name"
    ];
    
    for (NSString *t in supported) {
        if ([types containsObject:t]) {
            return YES;
        }
    }
    return NO;
}

static void runOnMainThread(dispatch_block_t block);

@interface NativeDropWindow : NSWindow
@end

@implementation NativeDropWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (BOOL)acceptsFirstResponder { return NO; }
@end

@class NativePlaylistDropBoxView;
static NSWindow *g_independentWindow = nil;
static NativePlaylistDropBoxView *g_independentDropBoxView = nil;
static bool g_dropWindowShouldBeVisible = false;

// Dedicated Compact Native AppKit Drop Companion View
@interface NativePlaylistDropBoxView : NSView <NSDraggingDestination>
@property (nonatomic, strong) NSTextField *headerLabel;
@property (nonatomic, strong) NSTextField *playlistLabel;
@property (nonatomic, strong) NSView *statusBadgeView;
@property (nonatomic, strong) NSTextField *statusLabel;

- (void)setTargetPlaylistName:(NSString *)name;
- (void)setStatusText:(NSString *)text statusType:(NSString *)type;
@end

@implementation NativePlaylistDropBoxView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        NSArray *dragTypes = @[
            NSPasteboardTypeURL,
            NSPasteboardTypeString,
            NSPasteboardTypeFileURL,
            @"public.url",
            @"public.file-url",
            @"public.utf8-plain-text",
            @"WebURLsWithTitlesPboardType",
            @"text/uri-list",
            @"NSURLPboardType",
            @"NSFilenamesPboardType"
        ];
        [self registerForDraggedTypes:dragTypes];
        
        [self setWantsLayer:YES];
        self.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.06 green:0.09 blue:0.16 alpha:0.96].CGColor;
        self.layer.borderColor = [NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:0.85].CGColor;
        self.layer.borderWidth = 2.0;
        self.layer.cornerRadius = 10.0;
        
        // 1. Drop YouTube Song Here
        _headerLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12, frameRect.size.height - 32, frameRect.size.width - 24, 22)];
        [_headerLabel setEditable:NO];
        [_headerLabel setSelectable:NO];
        [_headerLabel setBezeled:NO];
        [_headerLabel setDrawsBackground:NO];
        [_headerLabel setTextColor:[NSColor colorWithCalibratedRed:0.95 green:0.97 blue:1.0 alpha:1.0]];
        [_headerLabel setFont:[NSFont boldSystemFontOfSize:14]];
        [_headerLabel setAlignment:NSTextAlignmentCenter];
        [_headerLabel setStringValue:@"Drop YouTube Song Here"];
        [self addSubview:_headerLabel];
        
        // 2. Adds to: <Playlist Name>
        _playlistLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12, frameRect.size.height - 56, frameRect.size.width - 24, 20)];
        [_playlistLabel setEditable:NO];
        [_playlistLabel setSelectable:NO];
        [_playlistLabel setBezeled:NO];
        [_playlistLabel setDrawsBackground:NO];
        [_playlistLabel setTextColor:[NSColor colorWithCalibratedRed:0.58 green:0.64 blue:0.72 alpha:1.0]];
        [_playlistLabel setFont:[NSFont systemFontOfSize:12 weight:NSFontWeightMedium]];
        [_playlistLabel setAlignment:NSTextAlignmentCenter];
        [_playlistLabel setStringValue:@"Adds to: Select a Playlist"];
        [self addSubview:_playlistLabel];
        
        // 3. Status Badge Container View
        _statusBadgeView = [[NSView alloc] initWithFrame:NSMakeRect(16, 12, frameRect.size.width - 32, 42)];
        [_statusBadgeView setWantsLayer:YES];
        _statusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.12 green:0.16 blue:0.25 alpha:1.0].CGColor;
        _statusBadgeView.layer.cornerRadius = 6.0;
        [self addSubview:_statusBadgeView];
        
        // Status Text Label inside status badge
        _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(6, 8, frameRect.size.width - 44, 26)];
        [_statusLabel setEditable:NO];
        [_statusLabel setSelectable:NO];
        [_statusLabel setBezeled:NO];
        [_statusLabel setDrawsBackground:NO];
        [_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:1.0]];
        [_statusLabel setFont:[NSFont boldSystemFontOfSize:12]];
        [_statusLabel setAlignment:NSTextAlignmentCenter];
        [_statusLabel setStringValue:@"READY — Drop YouTube song here"];
        [_statusBadgeView addSubview:_statusLabel];
    }
    return self;
}

- (void)setTargetPlaylistName:(NSString *)name {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!name || name.length == 0) {
            [self->_playlistLabel setStringValue:@"NO PLAYLIST SELECTED"];
            [self->_playlistLabel setTextColor:[NSColor colorWithCalibratedRed:0.95 green:0.4 blue:0.4 alpha:1.0]];
        } else {
            [self->_playlistLabel setStringValue:[NSString stringWithFormat:@"Adds to: %@", name]];
            [self->_playlistLabel setTextColor:[NSColor colorWithCalibratedRed:0.58 green:0.64 blue:0.72 alpha:1.0]];
        }
    });
}

- (void)setStatusText:(NSString *)text statusType:(NSString *)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_statusLabel setStringValue:text ?: @"READY — Drop YouTube song here"];
        if ([type isEqualToString:@"drag_entered"]) {
            self->_statusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.08 green:0.45 blue:0.22 alpha:1.0].CGColor;
            [self->_statusLabel setTextColor:[NSColor whiteColor]];
        } else if ([type isEqualToString:@"adding"]) {
            self->_statusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.70 green:0.38 blue:0.05 alpha:1.0].CGColor;
            [self->_statusLabel setTextColor:[NSColor whiteColor]];
        } else if ([type isEqualToString:@"added"]) {
            self->_statusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.09 green:0.52 blue:0.24 alpha:1.0].CGColor;
            [self->_statusLabel setTextColor:[NSColor whiteColor]];
        } else if ([type isEqualToString:@"duplicate"]) {
            self->_statusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.76 green:0.26 blue:0.05 alpha:1.0].CGColor;
            [self->_statusLabel setTextColor:[NSColor whiteColor]];
        } else if ([type isEqualToString:@"error"]) {
            self->_statusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.72 green:0.11 blue:0.11 alpha:1.0].CGColor;
            [self->_statusLabel setTextColor:[NSColor whiteColor]];
        } else { // "ready" or default
            self->_statusBadgeView.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.12 green:0.16 blue:0.25 alpha:1.0].CGColor;
            [self->_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.22 green:0.74 blue:0.97 alpha:1.0]];
        }
    });
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    [self setStatusText:@"DRAG ENTERED" statusType:@"drag_entered"];
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [self setStatusText:@"READY — Drop YouTube song here" statusType:@"ready"];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *rawType = @"unknown";
    NSString *extracted = extractURLFromPasteboard(pboard, &rawType);
    
    NSPoint loc = [sender draggingLocation];
    NSRect bounds = self.bounds;
    float godot_x = (float)loc.x;
    float godot_y = (float)(bounds.size.height - loc.y);
    
    if (extracted && extracted.length > 0) {
        [self setStatusText:@"ADDING…" statusType:@"adding"];
        
        queue_external_event({
            "EXTERNAL_DROP",
            [rawType UTF8String] ?: "unknown",
            [extracted UTF8String] ?: "",
            godot_x,
            godot_y,
            (float)bounds.size.width,
            (float)bounds.size.height
        });
        return YES;
    }
    [self setStatusText:@"COULD NOT ADD — Invalid URL" statusType:@"error"];
    return NO;
}

@end

// Dedicated Full-Window Native Drag Destination Overlay
@interface NativeDragDestinationView : NSView <NSDraggingDestination>
@property (nonatomic, strong) NSTextField *debugBadge;
@end

@implementation NativeDragDestinationView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSArray *dragTypes = @[
            NSPasteboardTypeURL,
            NSPasteboardTypeString,
            NSPasteboardTypeFileURL,
            @"public.url",
            @"public.file-url",
            @"public.utf8-plain-text",
            @"WebURLsWithTitlesPboardType",
            @"NSFilenamesPboardType",
            @"text/uri-list",
            @"public.url-name"
        ];
        [self registerForDraggedTypes:dragTypes];
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        
        // Visible native indicator badge at top-right of window
        _debugBadge = [[NSTextField alloc] initWithFrame:NSMakeRect(frame.size.width - 270, frame.size.height - 32, 260, 26)];
        [_debugBadge setEditable:NO];
        [_debugBadge setSelectable:NO];
        [_debugBadge setBezeled:NO];
        [_debugBadge setDrawsBackground:YES];
        [_debugBadge setBackgroundColor:[NSColor colorWithCalibratedRed:0.0 green:0.3 blue:0.7 alpha:0.9]];
        [_debugBadge setTextColor:[NSColor whiteColor]];
        [_debugBadge setFont:[NSFont boldSystemFontOfSize:11]];
        [_debugBadge setAlignment:NSTextAlignmentCenter];
        [_debugBadge setStringValue:@"🟢 NATIVE DRAG RECEIVER READY"];
        [_debugBadge setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
        [self addSubview:_debugBadge];
        
        NSLog(@"[NATIVE_LOG] NativeDragDestinationView initialized with frame (%.1f, %.1f, %.1f, %.1f)", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
    }
    return self;
}

// FORWARD ALL ORDINARY MOUSE & KEYBOARD INPUTS STRAIGHT TO SUPERVIEW (GodotView)!
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { [self.superview mouseDown:event]; }
- (void)mouseUp:(NSEvent *)event { [self.superview mouseUp:event]; }
- (void)mouseDragged:(NSEvent *)event { [self.superview mouseDragged:event]; }
- (void)mouseMoved:(NSEvent *)event { [self.superview mouseMoved:event]; }
- (void)rightMouseDown:(NSEvent *)event { [self.superview rightMouseDown:event]; }
- (void)rightMouseUp:(NSEvent *)event { [self.superview rightMouseUp:event]; }
- (void)otherMouseDown:(NSEvent *)event { [self.superview otherMouseDown:event]; }
- (void)otherMouseUp:(NSEvent *)event { [self.superview otherMouseUp:event]; }
- (void)scrollWheel:(NSEvent *)event { [self.superview scrollWheel:event]; }
- (void)keyDown:(NSEvent *)event { [self.superview keyDown:event]; }
- (void)keyUp:(NSEvent *)event { [self.superview keyUp:event]; }

// APPCOCOA DRAG DESTINATION CALLBACKS
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSPoint loc = [sender draggingLocation];
    NSRect bounds = self.bounds;
    float godot_x = (float)loc.x;
    float godot_y = (float)(bounds.size.height - loc.y);
    
    NSString *typesStr = [[pboard types] componentsJoinedByString:@", "];
    NSLog(@"[NATIVE_LOG] EXTERNAL DRAG ENTERED (NativeDragDestinationView) types=%@", typesStr);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_debugBadge setStringValue:@"🟢 DRAG ENTERED NATIVE RECEIVER!"];
        [self->_debugBadge setBackgroundColor:[NSColor colorWithCalibratedRed:0.0 green:0.6 blue:0.2 alpha:0.95]];
    });
    
    if (isSupportedDragType(pboard)) {
        queue_external_event({
            "EXTERNAL_DRAG_ENTERED",
            [typesStr UTF8String] ?: "",
            "",
            godot_x,
            godot_y,
            (float)bounds.size.width,
            (float)bounds.size.height
        });
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    if (isSupportedDragType(pboard)) {
        NSPoint loc = [sender draggingLocation];
        NSRect bounds = self.bounds;
        float godot_x = (float)loc.x;
        float godot_y = (float)(bounds.size.height - loc.y);
        
        queue_external_event({
            "EXTERNAL_DRAG_UPDATED",
            "",
            "",
            godot_x,
            godot_y,
            (float)bounds.size.width,
            (float)bounds.size.height
        });
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_debugBadge setStringValue:@"🟢 NATIVE DRAG RECEIVER READY"];
        [self->_debugBadge setBackgroundColor:[NSColor colorWithCalibratedRed:0.0 green:0.3 blue:0.7 alpha:0.9]];
    });
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *typesStr = [[pboard types] componentsJoinedByString:@", "];
    NSLog(@"[NATIVE_LOG] EXTERNAL DROP CALLBACK RECEIVED (NativeDragDestinationView) types=%@", typesStr);
    
    NSString *rawType = @"unknown";
    NSString *extracted = extractURLFromPasteboard(pboard, &rawType);
    
    NSPoint loc = [sender draggingLocation];
    NSRect bounds = self.bounds;
    float godot_x = (float)loc.x;
    float godot_y = (float)(bounds.size.height - loc.y);
    
    if (extracted && extracted.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_debugBadge setStringValue:@"🎉 DROP RECEIVED NATIVE RECEIVER!"];
            [self->_debugBadge setBackgroundColor:[NSColor colorWithCalibratedRed:0.1 green:0.5 blue:0.9 alpha:0.95]];
        });
        
        queue_external_event({
            "EXTERNAL_DROP",
            [rawType UTF8String] ?: "unknown",
            [extracted UTF8String] ?: "",
            godot_x,
            godot_y,
            (float)bounds.size.width,
            (float)bounds.size.height
        });
        
        NSLog(@"[NATIVE_LOG] EXTERNAL PAYLOAD TYPE: %@ payload=%@", rawType, extracted);
        NSLog(@"[NATIVE_LOG] EXTERNAL DROP RECEIVED type=%@ payload_len=%lu loc=(%.1f, %.1f)",
              rawType, (unsigned long)extracted.length, godot_x, godot_y);
        return YES;
    }
    return NO;
}

@end

// Native Integration Test Harness: Mock object conforming to NSDraggingInfo
@interface MockDraggingInfo : NSObject <NSDraggingInfo>
@property (nonatomic, strong) NSPasteboard *pasteboard;
@property (nonatomic, assign) NSPoint location;
@end

@implementation MockDraggingInfo

- (instancetype)initWithPasteboard:(NSPasteboard *)pboard location:(NSPoint)loc {
    self = [super init];
    if (self) {
        _pasteboard = pboard;
        _location = loc;
    }
    return self;
}

- (NSWindow *)draggingDestinationWindow { return nil; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationCopy; }
- (NSPoint)draggingLocation { return _location; }
- (NSPoint)draggedImageLocation { return _location; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return _pasteboard; }
- (id)draggingSource { return nil; }
- (NSInteger)draggingSequenceNumber { return 1; }
- (void)slideDraggedImageTo:(NSPoint)screenPoint {}
- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination { return nil; }
- (NSInteger)numberOfValidItemsForDrop { return 1; }
- (void)setNumberOfValidItemsForDrop:(NSInteger)number {}
- (BOOL)animatesToDestination { return NO; }
- (void)setAnimatesToDestination:(BOOL)flag {}
- (NSDraggingFormation)draggingFormation { return NSDraggingFormationDefault; }
- (void)setDraggingFormation:(NSDraggingFormation)formation {}

@end

static bool run_native_receiver_test_impl(char *out_buf, size_t out_size) {
    int passCount = 0;
    const int targetCycles = 25;
    
    for (int cycle = 1; cycle <= targetCycles; ++cycle) {
        NSPasteboard *testPboard = [NSPasteboard pasteboardWithName:[NSString stringWithFormat:@"StudyCenterHubTestPboard_%d", cycle]];
        [testPboard clearContents];
        [testPboard declareTypes:@[NSPasteboardTypeURL, @"public.url"] owner:nil];
        [testPboard setString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=REAL_APPKIT_STRESS_TEST_%d", cycle] forType:NSPasteboardTypeURL];
        
        MockDraggingInfo *mock = [[MockDraggingInfo alloc] initWithPasteboard:testPboard location:NSMakePoint(100 + cycle, 100 + cycle)];
        
        ensure_external_drag_receiver();
        
        NativePlaylistDropBoxView *targetReceiver = g_independentDropBoxView;
        
        if (!targetReceiver || !g_independentWindow) {
            snprintf(out_buf, out_size, "success=false|cycle=%d|error=NativePlaylistDropBoxView not found in independent window", cycle);
            return false;
        }
        
        NSDragOperation op = [targetReceiver draggingEntered:mock];
        BOOL dropOk = [targetReceiver performDragOperation:mock];
        [targetReceiver draggingExited:mock];
        
        if (op != NSDragOperationNone && dropOk) {
            passCount++;
        } else {
            snprintf(out_buf, out_size, "success=false|cycle=%d|op=%ld|drop_ok=%s", cycle, (long)op, dropOk ? "true" : "false");
            return false;
        }
    }
    
    snprintf(out_buf, out_size, "success=true|pass_count=%d/%d|receiver_class=NativePlaylistDropBoxView|independent_window=created",
             passCount, targetCycles);
    return passCount == targetCycles;
}

typedef void (*RegisterForDraggedTypesIMP)(id, SEL, NSArray<NSPasteboardType>*);

static void custom_registerForDraggedTypes(id self, SEL _cmd, NSArray<NSPasteboardType> *types) {
    NSMutableArray *merged = [NSMutableArray arrayWithArray:types ?: @[]];
    NSArray *ourTypes = @[
        NSPasteboardTypeURL,
        NSPasteboardTypeString,
        NSPasteboardTypeFileURL,
        @"public.url",
        @"public.file-url",
        @"public.utf8-plain-text",
        @"WebURLsWithTitlesPboardType",
        @"NSFilenamesPboardType",
        @"text/uri-list",
        @"public.url-name"
    ];
    for (NSString *t in ourTypes) {
        if (![merged containsObject:t]) {
            [merged addObject:t];
        }
    }
    
    IMP orig = get_orig_imp([self class], _cmd);
    if (orig) {
        ((RegisterForDraggedTypesIMP)orig)(self, _cmd, merged);
    }
}

static NSDragOperation custom_draggingEntered(id self, SEL _cmd, id<NSDraggingInfo> sender) {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSPoint loc = [sender draggingLocation];
    NSRect bounds = [self respondsToSelector:@selector(bounds)] ? [self bounds] : NSMakeRect(0, 0, 1280, 800);
    float godot_x = (float)loc.x;
    float godot_y = (float)(bounds.size.height - loc.y);
    
    NSString *typesStr = [[pboard types] componentsJoinedByString:@", "];
    NSLog(@"[NATIVE_LOG] EXTERNAL DRAG ENTERED (%@) types=%@", [self className], typesStr);
    
    if (isSupportedDragType(pboard)) {
        queue_external_event({
            "EXTERNAL_DRAG_ENTERED",
            [typesStr UTF8String] ?: "",
            "",
            godot_x,
            godot_y,
            (float)bounds.size.width,
            (float)bounds.size.height
        });
        return NSDragOperationCopy;
    }
    
    IMP orig = get_orig_imp([self class], _cmd);
    if (orig) {
        return ((DragEnteredIMP)orig)(self, _cmd, sender);
    }
    return NSDragOperationNone;
}

static NSDragOperation custom_draggingUpdated(id self, SEL _cmd, id<NSDraggingInfo> sender) {
    NSPasteboard *pboard = [sender draggingPasteboard];
    if (isSupportedDragType(pboard)) {
        NSPoint loc = [sender draggingLocation];
        NSRect bounds = [self respondsToSelector:@selector(bounds)] ? [self bounds] : NSMakeRect(0, 0, 1280, 800);
        float godot_x = (float)loc.x;
        float godot_y = (float)(bounds.size.height - loc.y);
        
        queue_external_event({
            "EXTERNAL_DRAG_UPDATED",
            "",
            "",
            godot_x,
            godot_y,
            (float)bounds.size.width,
            (float)bounds.size.height
        });
        return NSDragOperationCopy;
    }
    
    IMP orig = get_orig_imp([self class], _cmd);
    if (orig) {
        return ((DragUpdatedIMP)orig)(self, _cmd, sender);
    }
    return NSDragOperationNone;
}

static BOOL custom_performDragOperation(id self, SEL _cmd, id<NSDraggingInfo> sender) {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSString *typesStr = [[pboard types] componentsJoinedByString:@", "];
    NSLog(@"[NATIVE_LOG] EXTERNAL DROP CALLBACK RECEIVED (%@) types=%@", [self className], typesStr);
    
    NSString *rawType = @"unknown";
    NSString *extracted = extractURLFromPasteboard(pboard, &rawType);
    
    NSPoint loc = [sender draggingLocation];
    NSRect bounds = [self respondsToSelector:@selector(bounds)] ? [self bounds] : NSMakeRect(0, 0, 1280, 800);
    float godot_x = (float)loc.x;
    float godot_y = (float)(bounds.size.height - loc.y);
    
    if (extracted && extracted.length > 0) {
        queue_external_event({
            "EXTERNAL_DROP",
            [rawType UTF8String] ?: "unknown",
            [extracted UTF8String] ?: "",
            godot_x,
            godot_y,
            (float)bounds.size.width,
            (float)bounds.size.height
        });
        
        NSLog(@"[NATIVE_LOG] EXTERNAL PAYLOAD TYPE: %@ payload=%@", rawType, extracted);
        NSLog(@"[NATIVE_LOG] EXTERNAL DROP RECEIVED type=%@ payload_len=%lu loc=(%.1f, %.1f)",
              rawType, (unsigned long)extracted.length, godot_x, godot_y);
        return YES;
    }
    
    IMP orig = get_orig_imp([self class], _cmd);
    if (orig) {
        return ((PerformDragIMP)orig)(self, _cmd, sender);
    }
    return NO;
}

static void setup_class_drag_swizzle(Class cls) {
    if (!cls) return;
    
    if (get_orig_imp(cls, @selector(draggingEntered:))) {
        return; // Already swizzled for this class
    }

    Method mRegister = class_getInstanceMethod(cls, @selector(registerForDraggedTypes:));
    if (mRegister) {
        IMP orig = method_getImplementation(mRegister);
        set_orig_imp(cls, @selector(registerForDraggedTypes:), orig);
        method_setImplementation(mRegister, (IMP)custom_registerForDraggedTypes);
    }

    Method mEntered = class_getInstanceMethod(cls, @selector(draggingEntered:));
    if (mEntered) {
        IMP orig = method_getImplementation(mEntered);
        set_orig_imp(cls, @selector(draggingEntered:), orig);
        method_setImplementation(mEntered, (IMP)custom_draggingEntered);
    } else {
        class_addMethod(cls, @selector(draggingEntered:), (IMP)custom_draggingEntered, "q@:@");
    }

    Method mUpdated = class_getInstanceMethod(cls, @selector(draggingUpdated:));
    if (mUpdated) {
        IMP orig = method_getImplementation(mUpdated);
        set_orig_imp(cls, @selector(draggingUpdated:), orig);
        method_setImplementation(mUpdated, (IMP)custom_draggingUpdated);
    } else {
        class_addMethod(cls, @selector(draggingUpdated:), (IMP)custom_draggingUpdated, "q@:@");
    }

    Method mPerform = class_getInstanceMethod(cls, @selector(performDragOperation:));
    if (mPerform) {
        IMP orig = method_getImplementation(mPerform);
        set_orig_imp(cls, @selector(performDragOperation:), orig);
        method_setImplementation(mPerform, (IMP)custom_performDragOperation);
    } else {
        class_addMethod(cls, @selector(performDragOperation:), (IMP)custom_performDragOperation, "B@:@");
    }
}

static NSWindow *getGodotMainWindow() {
    NSArray *wins = [NSApp windows];
    for (NSWindow *w in wins) {
        if ([w isVisible] && w.contentView && w != g_independentWindow) {
            NSString *clsName = [w className];
            if (![clsName isEqualToString:@"NSPanel"] && ![clsName isEqualToString:@"NativePlaylistDropBoxView"]) {
                return w;
            }
        }
    }
    for (NSWindow *w in wins) {
        if (w.contentView && w != g_independentWindow) {
            return w;
        }
    }
    return nil;
}

@interface DropWindowObserver : NSObject
@end

static DropWindowObserver *g_dropObserver = nil;

static void updateIndependentWindowPosition() {
    if (!g_independentWindow) return;
    
    NSWindow *mainWin = getGodotMainWindow();
    NSRect mainFrame = mainWin ? mainWin.frame : NSMakeRect(0, 0, 0, 0);
    if (mainFrame.size.width < 400 || mainFrame.size.height < 300) {
        NSScreen *screen = [NSScreen mainScreen];
        mainFrame = screen ? screen.visibleFrame : NSMakeRect(100, 100, 1440, 900);
    }

    CGFloat dropW = 440.0;
    CGFloat dropH = 130.0;
    CGFloat x = mainFrame.origin.x + mainFrame.size.width - dropW - 24.0;
    CGFloat y = mainFrame.origin.y + mainFrame.size.height - dropH - 54.0;

    NSRect newFrame = NSMakeRect(x, y, dropW, dropH);
    [g_independentWindow setFrame:newFrame display:YES animate:NO];
}

static void mac_wkwebview_cleanup_native();

@implementation DropWindowObserver
- (void)windowDidMoveOrResize:(NSNotification *)note {
    NSWindow *win = note.object;
    if (win && win != g_independentWindow) {
        updateIndependentWindowPosition();
    }
}
- (void)appDidHide:(NSNotification *)note {
    if (g_independentWindow) {
        [g_independentWindow orderOut:nil];
    }
}
- (void)appDidUnhide:(NSNotification *)note {
    if (g_independentWindow && g_dropWindowShouldBeVisible) {
        [g_independentWindow orderFrontRegardless];
    }
}
- (void)appWillTerminate:(NSNotification *)note {
    mac_wkwebview_cleanup_native();
}
- (void)windowWillClose:(NSNotification *)note {
    NSWindow *win = note.object;
    if (win && win != g_independentWindow) {
        mac_wkwebview_cleanup_native();
    }
}
@end

static uint64_t g_macos_keydown_count = 0;
static int g_macos_last_keycode = -1;
static int g_macos_last_char_count = 0;
static std::string g_macos_event_win_class = "nil";
static id g_macos_key_monitor = nil;

static void setup_passive_native_key_monitor() {
    if (g_macos_key_monitor) return;
    g_macos_key_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event && event.type == NSEventTypeKeyDown) {
            g_macos_keydown_count++;
            g_macos_last_keycode = (int)[event keyCode];
            NSString *chars = [event characters];
            g_macos_last_char_count = chars ? (int)chars.length : 0;
            NSWindow *win = event.window;
            g_macos_event_win_class = win ? [[win className] UTF8String] : "nil";
        }
        return event; // PASSIVE ONLY — NEVER MODIFY OR CONSUME EVENTS
    }];
}

static void mac_wkwebview_cleanup_native() {
    g_dropWindowShouldBeVisible = false;
    if (g_macos_key_monitor) {
        [NSEvent removeMonitor:g_macos_key_monitor];
        g_macos_key_monitor = nil;
    }
    if (g_dropObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:g_dropObserver];
        g_dropObserver = nil;
    }
    if (g_independentWindow) {
        [g_independentWindow orderOut:nil];
        [g_independentWindow close];
        g_independentWindow = nil;
    }
    g_independentDropBoxView = nil;
    NSLog(@"[NATIVE_LOG] mac_wkwebview_cleanup_native executed cleanly.");
}

static void ensure_external_drag_receiver() {
    setup_passive_native_key_monitor();
    g_diag_info.bridge_loaded = true;
    
    NSArray *dragTypes = @[
        NSPasteboardTypeURL,
        NSPasteboardTypeString,
        NSPasteboardTypeFileURL,
        @"public.url",
        @"public.file-url",
        @"public.utf8-plain-text",
        @"WebURLsWithTitlesPboardType",
        @"NSFilenamesPboardType",
        @"text/uri-list",
        @"public.url-name"
    ];
    g_diag_info.registered_types = [[dragTypes componentsJoinedByString:@", "] UTF8String];

    NSWindow *mainWin = getGodotMainWindow();

    g_diag_info.app_ptr = [NSString stringWithFormat:@"%p", NSApp].UTF8String;
    g_diag_info.app_activation_policy = (int)[NSApp activationPolicy];
    g_diag_info.app_is_active = [NSApp isActive];

    if (mainWin) {
        g_diag_info.window_found = true;
        g_diag_info.main_window_ptr = [NSString stringWithFormat:@"%p", mainWin].UTF8String;
    } else {
        g_diag_info.window_found = false;
        g_diag_info.main_window_ptr = "nil";
    }

    NSWindow *keyWin = [NSApp keyWindow];
    g_diag_info.key_window_ptr = keyWin ? [NSString stringWithFormat:@"%p", keyWin].UTF8String : "nil";

    if (!g_independentWindow) {
        NSRect winFrame = mainWin ? mainWin.frame : NSMakeRect(0, 0, 0, 0);
        if (winFrame.size.width < 400 || winFrame.size.height < 300) {
            NSScreen *screen = [NSScreen mainScreen];
            winFrame = screen ? screen.visibleFrame : NSMakeRect(100, 100, 1440, 900);
        }

        CGFloat dropW = 440.0;
        CGFloat dropH = 130.0;
        CGFloat x = winFrame.origin.x + winFrame.size.width - dropW - 24.0;
        CGFloat y = winFrame.origin.y + winFrame.size.height - dropH - 54.0;
        NSRect indFrame = NSMakeRect(x, y, dropW, dropH);

        NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_independentWindow = [[NativeDropWindow alloc] initWithContentRect:indFrame
                                                                  styleMask:styleMask
                                                                    backing:NSBackingStoreBuffered
                                                                      defer:NO];
        [g_independentWindow setTitle:@"Drop YouTube Song Here"];
        [g_independentWindow setLevel:NSFloatingWindowLevel];
        [g_independentWindow setHidesOnDeactivate:YES];
        [g_independentWindow setHasShadow:YES];
        [g_independentWindow setReleasedWhenClosed:NO];

        g_independentDropBoxView = [[NativePlaylistDropBoxView alloc] initWithFrame:[g_independentWindow.contentView bounds]];
        [g_independentDropBoxView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [g_independentDropBoxView registerForDraggedTypes:dragTypes];

        [g_independentWindow.contentView addSubview:g_independentDropBoxView];
        [g_independentWindow registerForDraggedTypes:dragTypes];

        if (!g_dropObserver) {
            g_dropObserver = [[DropWindowObserver alloc] init];
            NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
            [nc addObserver:g_dropObserver selector:@selector(windowDidMoveOrResize:) name:NSWindowDidMoveNotification object:nil];
            [nc addObserver:g_dropObserver selector:@selector(windowDidMoveOrResize:) name:NSWindowDidResizeNotification object:nil];
            [nc addObserver:g_dropObserver selector:@selector(appDidHide:) name:NSApplicationDidHideNotification object:nil];
            [nc addObserver:g_dropObserver selector:@selector(appDidUnhide:) name:NSApplicationDidUnhideNotification object:nil];
            [nc addObserver:g_dropObserver selector:@selector(appWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
            if (mainWin) {
                [nc addObserver:g_dropObserver selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:mainWin];
            }
        }

        if (g_dropWindowShouldBeVisible) {
            [g_independentWindow orderFrontRegardless];
        } else {
            [g_independentWindow orderOut:nil];
        }
        
        // Always ensure Godot's main window retains key window status
        if (mainWin) {
            [mainWin makeKeyAndOrderFront:nil];
        }
        NSLog(@"[NATIVE_LOG] Created compact production independent NativeDropWindow (%p) with parentWindow=NIL", g_independentWindow);
    } else {
        if (g_dropWindowShouldBeVisible) {
            [g_independentWindow orderFrontRegardless];
        } else {
            [g_independentWindow orderOut:nil];
        }
        if (mainWin) {
            [mainWin makeKeyAndOrderFront:nil];
        }
    }

    g_diag_info.independent_window_ptr = [NSString stringWithFormat:@"%p", g_independentWindow].UTF8String;
    g_diag_info.independent_parent_ptr = g_independentWindow.parentWindow ? [NSString stringWithFormat:@"%p", g_independentWindow.parentWindow].UTF8String : "nil";
    g_diag_info.independent_window_class = [[g_independentWindow className] UTF8String];
    g_diag_info.independent_window_level = (long)g_independentWindow.level;
    g_diag_info.independent_style_mask = (unsigned long)g_independentWindow.styleMask;
    g_diag_info.independent_is_visible = [g_independentWindow isVisible];
    g_diag_info.independent_ignores_mouse = [g_independentWindow ignoresMouseEvents];
    g_diag_info.independent_content_view_class = g_independentWindow.contentView ? [[g_independentWindow.contentView className] UTF8String] : "None";

    g_diag_info.receiver_window_ptr = g_independentDropBoxView ? [NSString stringWithFormat:@"%p", g_independentDropBoxView.window].UTF8String : "nil";
    g_diag_info.receiver_class = g_independentDropBoxView ? [[g_independentDropBoxView className] UTF8String] : "None";

    bool hasNoParent = (g_independentWindow.parentWindow == nil);
    bool isReceiverInInd = (g_independentDropBoxView.window == g_independentWindow);
    bool isVisible = [g_independentWindow isVisible];

    g_diag_info.receiver_attached = (g_independentWindow != nil && hasNoParent && isReceiverInInd);
    g_diag_info.receiver_enabled = g_diag_info.receiver_attached && isVisible;

    NSRect curFrame = g_independentWindow.frame;
    char frameBuf[128];
    snprintf(frameBuf, sizeof(frameBuf), "%.1f, %.1f, %.1f, %.1f", curFrame.origin.x, curFrame.origin.y, curFrame.size.width, curFrame.size.height);
    g_diag_info.frame_str = frameBuf;

    g_drag_bridge_initialized = true;
}

static void mac_wkwebview_set_drag_box_visible(bool visible) {
    runOnMainThread(^{
        g_dropWindowShouldBeVisible = visible;
        if (visible) {
            ensure_external_drag_receiver();
            if (g_independentWindow) {
                updateIndependentWindowPosition();
                [g_independentWindow orderFrontRegardless];
            }
        } else {
            if (g_independentWindow) {
                [g_independentWindow orderOut:nil];
            }
        }
        NSWindow *mainWin = getGodotMainWindow();
        if (mainWin) {
            [mainWin makeKeyAndOrderFront:nil];
        }
    });
}

static void enable_external_drag_drop_native() {
    dispatch_async(dispatch_get_main_queue(), ^{
        ensure_external_drag_receiver();
        NSLog(@"[NATIVE_LOG] enable_external_drag_drop_native executed (Version: %s)", NATIVE_DRAG_BRIDGE_VERSION_STR);
    });
}



struct PlayerEvent {
    std::string name;
    std::string data;
};

@interface MacWKWebViewBridge : NSObject <WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, assign) std::mutex *eventMutex;
@property (nonatomic, assign) std::vector<PlayerEvent> *eventQueue;
@end

@implementation MacWKWebViewBridge
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"godotBridge"]) {
        NSDictionary *dict = message.body;
        if ([dict isKindOfClass:[NSDictionary class]]) {
            NSString *eventName = dict[@"event"];
            NSDictionary *dataDict = dict[@"data"] ?: @{};
            NSError *error = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataDict options:0 error:&error];
            NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
            
            if (eventName && self.eventMutex && self.eventQueue) {
                std::lock_guard<std::mutex> lock(*self.eventMutex);
                self.eventQueue->push_back({ [eventName UTF8String], [jsonStr UTF8String] });
            }
        }
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    printf("[NATIVE_LOG] WKWEBVIEW_NAVIGATION_SUCCESS url=%s\n", [[webView.URL absoluteString] UTF8String] ?: "");
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    printf("[NATIVE_LOG] WKWEBVIEW_NAVIGATION_FAILURE code=%ld description=%s\n", (long)error.code, [[error localizedDescription] UTF8String] ?: "");
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    printf("[NATIVE_LOG] WKWEBVIEW_PROVISIONAL_NAVIGATION_FAILURE code=%ld description=%s\n", (long)error.code, [[error localizedDescription] UTF8String] ?: "");
}
@end

struct NativePlayerHost {
    WKWebView *webView;
    MacWKWebViewBridge *bridge;
    std::mutex eventMutex;
    std::vector<PlayerEvent> eventQueue;
};

static void runOnMainThread(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static NSString *getTestHTMLTemplate() {
    return @"<!DOCTYPE html>\n"
    "<html>\n"
    "<head>\n"
    "  <meta charset=\"utf-8\">\n"
    "  <style>\n"
    "    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #0b0f19; color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; }\n"
    "    .card { border: 3px solid #4cd964; padding: 24px 32px; border-radius: 14px; background: #141b2d; text-align: center; box-shadow: 0 8px 24px rgba(0,0,0,0.6); }\n"
    "    h1 { color: #4cd964; margin: 0 0 10px 0; font-size: 22px; letter-spacing: 0.5px; }\n"
    "    p { color: #e2e8f0; margin: 6px 0; font-size: 15px; }\n"
    "    .badge { display: inline-block; background: #2e7d56; color: #ffffff; padding: 4px 12px; border-radius: 6px; font-weight: bold; margin-top: 10px; font-size: 13px; }\n"
    "  </style>\n"
    "</head>\n"
    "<body>\n"
    "  <div class=\"card\">\n"
    "    <h1>STUDYCENTERHUB WEBVIEW TEST</h1>\n"
    "    <p style=\"color:#4cd964; font-weight:bold;\">✅ GATE A: WKWebView Native Surface Active!</p>\n"
    "    <p id=\"clock\">System Time: Loading...</p>\n"
    "    <div class=\"badge\">NATIVE MACOS WKWEBVIEW HOST</div>\n"
    "  </div>\n"
    "  <script>\n"
    "    setInterval(function() {\n"
    "      document.getElementById('clock').innerText = 'System Time: ' + new Date().toLocaleTimeString();\n"
    "    }, 500);\n"
    "  </script>\n"
    "</body>\n"
    "</html>";
}

static NSString *getHTMLTemplate() {
    return @"<!DOCTYPE html>\n"
    "<html>\n"
    "<head>\n"
    "  <meta charset=\"utf-8\">\n"
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
    "  <style>\n"
    "    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #0b0f19; overflow: hidden; }\n"
    "    #player { width: 100%; height: 100%; border: none; }\n"
    "  </style>\n"
    "</head>\n"
    "<body>\n"
    "  <div id=\"player\"></div>\n"
    "  <script>\n"
    "    var tag = document.createElement('script');\n"
    "    tag.src = 'https://www.youtube.com/iframe_api';\n"
    "    var firstScriptTag = document.getElementsByTagName('script')[0];\n"
    "    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);\n"
    "    var player = null;\n"
    "    var isReady = false;\n"
    "    var pendingVideoId = null;\n"
    "    function sendToGodot(event, data) {\n"
    "      try {\n"
    "        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godotBridge) {\n"
    "          window.webkit.messageHandlers.godotBridge.postMessage({\n"
    "            event: event,\n"
    "            data: data || {}\n"
    "          });\n"
    "        }\n"
    "      } catch (e) { console.error(e); }\n"
    "    }\n"
    "    function onYouTubeIframeAPIReady() {\n"
    "      player = new YT.Player('player', {\n"
    "        height: '100%',\n"
    "        width: '100%',\n"
    "        playerVars: {\n"
    "          'autoplay': 1,\n"
    "          'controls': 1,\n"
    "          'enablejsapi': 1,\n"
    "          'origin': window.location.origin,\n"
    "          'playsinline': 1\n"
    "        },\n"
    "        events: {\n"
    "          'onReady': onPlayerReady,\n"
    "          'onStateChange': onPlayerStateChange,\n"
    "          'onError': onPlayerError\n"
    "        }\n"
    "      });\n"
    "    }\n"
    "    function onPlayerReady(event) {\n"
    "      isReady = true;\n"
    "      sendToGodot('READY', {});\n"
    "      if (pendingVideoId) {\n"
    "        var vid = pendingVideoId;\n"
    "        pendingVideoId = null;\n"
    "        player.loadVideoById(vid);\n"
    "      }\n"
    "    }\n"
    "    function onPlayerStateChange(event) {\n"
    "      if (event.data === 1) { sendToGodot('PLAYING', {}); }\n"
    "      else if (event.data === 2) { sendToGodot('PAUSED', {}); }\n"
    "      else if (event.data === 0) { sendToGodot('ENDED', {}); }\n"
    "    }\n"
    "    function onPlayerError(event) { sendToGodot('ERROR', { code: event.data }); }\n"
    "    function loadVideo(videoId) {\n"
    "      if (isReady && player && typeof player.loadVideoById === 'function') {\n"
    "        player.loadVideoById(videoId);\n"
    "      } else {\n"
    "        pendingVideoId = videoId;\n"
    "      }\n"
    "    }\n"

    "    function playVideo() {\n"
    "      if (isReady && player && typeof player.playVideo === 'function') {\n"
    "        player.playVideo();\n"
    "      }\n"
    "    }\n"
    "    function pauseVideo() {\n"
    "      if (isReady && player && typeof player.pauseVideo === 'function') {\n"
    "        player.pauseVideo();\n"
    "      }\n"
    "    }\n"
    "    function stopVideo() {\n"
    "      if (isReady && player && typeof player.stopVideo === 'function') {\n"
    "        player.stopVideo();\n"
    "      }\n"
    "    }\n"
    "  </script>\n"
    "</body>\n"
    "</html>";
}static NSString *extractCleanVideoId(NSString *inputStr) {
    if (!inputStr || [inputStr length] == 0) return @"M7lc1UVf-VE";
    NSString *clean = [inputStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([clean length] == 11 && [clean rangeOfString:@"/"].location == NSNotFound && [clean rangeOfString:@":"].location == NSNotFound) {
        return clean;
    }
    if ([clean rangeOfString:@"v="].location != NSNotFound) {
        NSArray *components = [clean componentsSeparatedByString:@"v="];
        if (components.count > 1) {
            NSString *candidate = [components[1] componentsSeparatedByString:@"&"][0];
            candidate = [candidate componentsSeparatedByString:@"?"][0];
            candidate = [candidate componentsSeparatedByString:@"#"][0];
            if ([candidate length] >= 11) return [candidate substringToIndex:11];
        }
    }
    if ([clean rangeOfString:@"youtu.be/"].location != NSNotFound) {
        NSArray *components = [clean componentsSeparatedByString:@"youtu.be/"];
        if (components.count > 1) {
            NSString *candidate = [components[1] componentsSeparatedByString:@"?"][0];
            candidate = [candidate componentsSeparatedByString:@"#"][0];
            if ([candidate length] >= 11) return [candidate substringToIndex:11];
        }
    }
    if ([clean rangeOfString:@"embed/"].location != NSNotFound) {
        NSArray *components = [clean componentsSeparatedByString:@"embed/"];
        if (components.count > 1) {
            NSString *candidate = [components[1] componentsSeparatedByString:@"?"][0];
            candidate = [candidate componentsSeparatedByString:@"#"][0];
            if ([candidate length] >= 11) return [candidate substringToIndex:11];
        }
    }
    return clean;
}

static void loadHTMLContainer(WKWebView *webView, NSString *initialVideoId) {
    if (!webView) return;
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleId || [bundleId length] == 0) {
        bundleId = @"org.godotengine.godot";
    }
    printf("[NATIVE_LOG] STUDYCENTERHUB_BUNDLE_ID=%s\n", [bundleId UTF8String]);

    NSString *refererStr = [NSString stringWithFormat:@"https://%@", bundleId];
    printf("[NATIVE_LOG] REFERER_IDENTITY_SUPPLIED=%s\n", [refererStr UTF8String]);

    NSString *cleanId = extractCleanVideoId(initialVideoId);
    printf("[NATIVE_LOG] INITIAL_VIDEO_ID=%s\n", [cleanId UTF8String]);

    [webView loadHTMLString:getHTMLTemplate() baseURL:[NSURL URLWithString:refererStr]];
}

@interface MacWKWebViewHostView : WKWebView
@end

@implementation MacWKWebViewHostView
- (NSView *)hitTest:(NSPoint)point {
    if (self.isHidden) {
        return nil;
    }
    NSPoint localPoint = [self convertPoint:point fromView:self.superview];
    if (!NSPointInRect(localPoint, self.bounds)) {
        return nil;
    }
    printf("[NATIVE_LOG] WKWEBVIEW_HIT_TEST_INSIDE point=(%.1f, %.1f) bounds=(%.1f, %.1f, %.1f, %.1f)\n", point.x, point.y, self.frame.origin.x, self.frame.origin.y, self.frame.size.width, self.frame.size.height);
    return [super hitTest:point];
}
@end

extern "C" {

uint64_t mac_wkwebview_create(uint64_t view_or_window_handle, float x, float y, float w, float h) {
    NativePlayerHost *host = new NativePlayerHost();
    printf("[NATIVE_LOG] WKWEBVIEW_CREATE_REQUEST view_handle=%llu x=%.1f y=%.1f w=%.1f h=%.1f\n", (unsigned long long)view_or_window_handle, x, y, w, h);
    
    runOnMainThread(^{
        NSView *parentView = nil;
        if (view_or_window_handle != 0) {
            id obj = (__bridge id)(void*)view_or_window_handle;
            if ([obj isKindOfClass:[NSWindow class]]) {
                parentView = [(NSWindow *)obj contentView];
            } else if ([obj isKindOfClass:[NSView class]]) {
                parentView = (NSView *)obj;
            } else if ([obj respondsToSelector:@selector(contentView)]) {
                parentView = [obj performSelector:@selector(contentView)];
            }
        }
        
        if (!parentView) {
            NSWindow *mainWin = [NSApp mainWindow] ?: [[NSApp windows] firstObject];
            if (mainWin) {
                parentView = [mainWin contentView];
            }
        }
        
        CGFloat parentH = parentView ? parentView.bounds.size.height : 800.0;
        NSRect frame = NSMakeRect(x, parentH - y - h, w, h);
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        
        MacWKWebViewBridge *bridge = [[MacWKWebViewBridge alloc] init];
        bridge.eventMutex = &host->eventMutex;
        bridge.eventQueue = &host->eventQueue;
        host->bridge = bridge;
        
        WKUserContentController *userContent = [[WKUserContentController alloc] init];
        [userContent addScriptMessageHandler:bridge name:@"godotBridge"];
        config.userContentController = userContent;
        
        MacWKWebViewHostView *webView = [[MacWKWebViewHostView alloc] initWithFrame:frame configuration:config];
        webView.wantsLayer = YES;
        if (webView.layer) {
            webView.layer.zPosition = 1.0;
        }
        webView.navigationDelegate = bridge;
        bridge.webView = webView;
        host->webView = webView;
        
        printf("[NATIVE_LOG] WKWEBVIEW_CREATE_RESULT success=true handle=%llu\n", (unsigned long long)host);
        
        if (parentView) {
            parentView.wantsLayer = YES;
            [parentView addSubview:webView positioned:NSWindowAbove relativeTo:nil];
            printf("[NATIVE_LOG] WKWEBVIEW_ATTACHED parentClass=%s windowTitle=%s bounds=(%.1f, %.1f)\n",
                object_getClassName(parentView),
                [[parentView.window title] UTF8String] ?: "MainWindow",
                parentView.bounds.size.width, parentView.bounds.size.height);
        } else {
            printf("[NATIVE_LOG] WKWEBVIEW_ATTACHED parentView=NIL (no container view found)\n");
        }

        loadHTMLContainer(webView, @"M7lc1UVf-VE");
        printf("[NATIVE_LOG] HTML_LOAD_FINISHED success=true\n");
    });
    
    return (uint64_t)host;
}


void mac_wkwebview_load_video(uint64_t handle_val, const char* video_id) {
    if (!handle_val || !video_id) return;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    NSString *vId = [NSString stringWithUTF8String:video_id];
    NSString *cleanId = extractCleanVideoId(vId);
    printf("[NATIVE_LOAD_VIDEO_RECEIVED] raw_vid='%s' clean_vid='%s' webview_exists=%s\n", [vId UTF8String] ?: "", [cleanId UTF8String] ?: "", (host && host->webView) ? "true" : "false");
    runOnMainThread(^{
        if (host && host->webView) {
            NSString *jsCode = [NSString stringWithFormat:@"loadVideo('%@');", cleanId];
            [host->webView evaluateJavaScript:jsCode completionHandler:^(id result, NSError *error) {
                if (error) {
                    printf("[NATIVE_LOG] EVAL_LOAD_VIDEO_ERROR: %s\n", [[error localizedDescription] UTF8String] ?: "");
                } else {
                    printf("[NATIVE_LOG] EVAL_LOAD_VIDEO_SUCCESS: video_id=%s\n", [cleanId UTF8String]);
                }
            }];
        }
    });
}



void mac_wkwebview_play(uint64_t handle_val) {
    if (!handle_val) return;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    runOnMainThread(^{
        if (host->webView) {
            [host->webView evaluateJavaScript:@"playVideo();" completionHandler:nil];
        }
    });
}

void mac_wkwebview_pause(uint64_t handle_val) {
    if (!handle_val) return;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    runOnMainThread(^{
        if (host->webView) {
            [host->webView evaluateJavaScript:@"pauseVideo();" completionHandler:nil];
        }
    });
}

void mac_wkwebview_stop(uint64_t handle_val) {
    if (!handle_val) return;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    runOnMainThread(^{
        if (host->webView) {
            [host->webView evaluateJavaScript:@"stopVideo();" completionHandler:nil];
        }
    });
}

void mac_wkwebview_set_bounds(uint64_t handle_val, float x, float y, float w, float h) {
    if (!handle_val) return;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    runOnMainThread(^{
        if (host->webView && host->webView.superview) {
            CGFloat parentH = host->webView.superview.bounds.size.height;
            NSRect frame = NSMakeRect(x, parentH - y - h, w, h);
            [host->webView setFrame:frame];
        }
    });
}

void mac_wkwebview_set_visible(uint64_t handle_val, bool visible) {
    if (!handle_val) return;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    runOnMainThread(^{
        if (host->webView) {
            host->webView.hidden = !visible;
        }
    });
}

void mac_wkwebview_destroy(uint64_t handle_val) {
    if (!handle_val) return;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    runOnMainThread(^{
        if (host->webView) {
            [host->webView removeFromSuperview];
            host->webView = nil;
        }
        delete host;
    });
}

bool mac_wkwebview_poll_event(uint64_t handle_val, char* out_event_buf, int event_buf_size, char* out_data_buf, int data_buf_size) {
    if (!handle_val) return false;
    NativePlayerHost *host = (NativePlayerHost*)handle_val;
    std::lock_guard<std::mutex> lock(host->eventMutex);
    if (host->eventQueue.empty()) {
        return false;
    }
    PlayerEvent ev = host->eventQueue.front();
    host->eventQueue.erase(host->eventQueue.begin());
    
    snprintf(out_event_buf, event_buf_size, "%s", ev.name.c_str());
    snprintf(out_data_buf, data_buf_size, "%s", ev.data.c_str());
    return true;
}

// Engine GDExtension initialization entry point
static GDExtensionInterfaceStringNameNewWithUtf8Chars p_string_name_new = nullptr;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 p_register_class = nullptr;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod p_register_method = nullptr;
static GDExtensionInterfaceClassdbConstructObject3 p_construct_object = nullptr;
static GDExtensionInterfaceGetVariantToTypeConstructor p_get_variant_to_type = nullptr;
static GDExtensionInterfaceGetVariantFromTypeConstructor p_get_variant_from_type = nullptr;
static GDExtensionInterfaceStringToUtf8Chars p_string_to_utf8 = nullptr;
typedef void (*GDExtensionInterfaceStringNewWithUtf8Func)(GDExtensionUninitializedStringPtr r_dest, const char *p_contents, GDExtensionInt p_size);
static GDExtensionInterfaceStringNewWithUtf8Func p_string_new_utf8 = nullptr;

static GDExtensionTypeFromVariantConstructorFunc conv_from_int = nullptr;
static GDExtensionTypeFromVariantConstructorFunc conv_from_float = nullptr;
static GDExtensionTypeFromVariantConstructorFunc conv_from_bool = nullptr;
static GDExtensionTypeFromVariantConstructorFunc conv_from_string = nullptr;

static GDExtensionVariantFromTypeConstructorFunc conv_to_int = nullptr;
static GDExtensionVariantFromTypeConstructorFunc conv_to_string = nullptr;
static GDExtensionVariantFromTypeConstructorFunc conv_to_bool = nullptr;

static void call_create_player(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint64_t handle = 0;
    double x = 0, y = 0, w = 0, h = 0;
    int64_t raw_handle = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&raw_handle, (GDExtensionVariantPtr)args[0]);
    if (arg_count > 1 && args[1] && conv_from_float) conv_from_float(&x, (GDExtensionVariantPtr)args[1]);
    if (arg_count > 2 && args[2] && conv_from_float) conv_from_float(&y, (GDExtensionVariantPtr)args[2]);
    if (arg_count > 3 && args[3] && conv_from_float) conv_from_float(&w, (GDExtensionVariantPtr)args[3]);
    if (arg_count > 4 && args[4] && conv_from_float) conv_from_float(&h, (GDExtensionVariantPtr)args[4]);
    
    handle = mac_wkwebview_create((uint64_t)raw_handle, (float)x, (float)y, (float)w, (float)h);
    
    if (r_return && conv_to_int) {
        int64_t ret64 = (int64_t)handle;
        conv_to_int(r_return, &ret64);
    }
}

static void extract_utf8_from_variant(GDExtensionConstVariantPtr p_variant, char *out_buf, int max_len) {
    memset(out_buf, 0, max_len);
    if (!p_variant) return;
    
    uint8_t godot_string[128] = {0};
    if (conv_from_string && p_string_to_utf8) {
        conv_from_string(godot_string, (GDExtensionVariantPtr)p_variant);
        GDExtensionInt len = p_string_to_utf8(godot_string, out_buf, max_len - 1);
        if (len >= 0 && len < max_len) {
            out_buf[len] = '\0';
        }
    }
}

static void call_load_video(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    
    char vid_buf[256] = {0};
    if (arg_count > 1 && args[1]) {
        extract_utf8_from_variant(args[1], vid_buf, sizeof(vid_buf));
    }
    
    printf("[NATIVE_LOG] call_load_video handle=%lld raw_vid='%s' len=%zu\n", (long long)handle, vid_buf, strlen(vid_buf));
    mac_wkwebview_load_video((uint64_t)handle, vid_buf);
}



static void call_play_video(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    mac_wkwebview_play((uint64_t)handle);
}

static void call_pause_video(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    mac_wkwebview_pause((uint64_t)handle);
}

static void call_stop_video(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    mac_wkwebview_stop((uint64_t)handle);
}

static void call_set_bounds(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    double x = 0, y = 0, w = 0, h = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    if (arg_count > 1 && args[1] && conv_from_float) conv_from_float(&x, (GDExtensionVariantPtr)args[1]);
    if (arg_count > 2 && args[2] && conv_from_float) conv_from_float(&y, (GDExtensionVariantPtr)args[2]);
    if (arg_count > 3 && args[3] && conv_from_float) conv_from_float(&w, (GDExtensionVariantPtr)args[3]);
    if (arg_count > 4 && args[4] && conv_from_float) conv_from_float(&h, (GDExtensionVariantPtr)args[4]);
    mac_wkwebview_set_bounds((uint64_t)handle, (float)x, (float)y, (float)w, (float)h);
}

static void call_set_visible(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    uint8_t vis = 1;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    if (arg_count > 1 && args[1] && conv_from_bool) conv_from_bool(&vis, (GDExtensionVariantPtr)args[1]);
    mac_wkwebview_set_visible((uint64_t)handle, vis != 0);
}

static void call_destroy_player(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    mac_wkwebview_destroy((uint64_t)handle);
}

static void call_poll_event(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle = 0;
    if (arg_count > 0 && args[0] && conv_from_int) conv_from_int(&handle, (GDExtensionVariantPtr)args[0]);
    
    char ev[128] = {0};
    char dt[1024] = {0};
    bool ok = mac_wkwebview_poll_event((uint64_t)handle, ev, sizeof(ev), dt, sizeof(dt));
    
    char formatted_res[2048] = {0};
    if (ok) {
        snprintf(formatted_res, sizeof(formatted_res), "%s|%s", ev, dt);
    }
    
    if (r_return && conv_to_string && p_string_new_utf8) {
        uint8_t godot_str[64] = {0};
        p_string_new_utf8(godot_str, formatted_res, strlen(formatted_res));
        conv_to_string(r_return, godot_str);
    }
}

static void call_enable_external_drag(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    enable_external_drag_drop_native();
}

static void call_poll_external_drop(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    std::string result_str = "";
    {
        std::lock_guard<std::mutex> lock(g_drop_mutex);
        if (!g_drop_events.empty()) {
            ExternalDropEvent ev = g_drop_events.front();
            g_drop_events.erase(g_drop_events.begin());
            
            char buf[4096] = {0};
            snprintf(buf, sizeof(buf), "%s|%s|%.1f|%.1f|%.1f|%.1f|%s",
                     ev.event.c_str(), ev.raw_type.c_str(), ev.x, ev.y, ev.window_w, ev.window_h, ev.payload.c_str());
            result_str = buf;
        }
    }
    
    if (r_return && conv_to_string && p_string_new_utf8) {
        uint8_t godot_str[64] = {0};
        p_string_new_utf8(godot_str, result_str.c_str(), result_str.length());
        conv_to_string(r_return, godot_str);
    }
}

static void call_update_target_playlist(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    char name_buf[512] = {0};
    if (arg_count > 0 && args[0]) {
        extract_utf8_from_variant(args[0], name_buf, sizeof(name_buf));
    }
    NSString *nsName = [NSString stringWithUTF8String:name_buf];
    runOnMainThread(^{
        if (g_independentDropBoxView) {
            [g_independentDropBoxView setTargetPlaylistName:nsName];
        }
    });
}

static void call_update_drop_status(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    char text_buf[512] = {0};
    char type_buf[64] = {0};
    if (arg_count > 0 && args[0]) extract_utf8_from_variant(args[0], text_buf, sizeof(text_buf));
    if (arg_count > 1 && args[1]) extract_utf8_from_variant(args[1], type_buf, sizeof(type_buf));
    
    NSString *nsText = [NSString stringWithUTF8String:text_buf];
    NSString *nsType = [NSString stringWithUTF8String:type_buf];
    runOnMainThread(^{
        if (g_independentDropBoxView) {
            [g_independentDropBoxView setStatusText:nsText statusType:nsType];
        }
    });
}

static void call_set_drag_box_visible(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t vis = 1;
    if (arg_count > 0 && args[0] && conv_from_bool) conv_from_bool(&vis, (GDExtensionVariantPtr)args[0]);
    mac_wkwebview_set_drag_box_visible(vis != 0);
}

static void call_get_native_diagnostics(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    setup_passive_native_key_monitor();
    NSWindow *mainWin = getGodotMainWindow();
    NSWindow *keyWin = [NSApp keyWindow];
    
    NSString *keyClass = keyWin ? [keyWin className] : @"nil";
    NSString *keyPtr = keyWin ? [NSString stringWithFormat:@"%p", keyWin] : @"nil";
    NSString *mainClass = mainWin ? [mainWin className] : @"nil";
    NSString *mainPtr = mainWin ? [NSString stringWithFormat:@"%p", mainWin] : @"nil";
    
    BOOL godotIsKey = mainWin ? [mainWin isKeyWindow] : NO;
    BOOL godotIsMain = mainWin ? [mainWin isMainWindow] : NO;

    BOOL indCreated = (g_independentWindow != nil);
    BOOL indVisible = indCreated ? [g_independentWindow isVisible] : NO;
    BOOL indIsKey = indCreated ? [g_independentWindow isKeyWindow] : NO;
    BOOL indIsMain = indCreated ? [g_independentWindow isMainWindow] : NO;
    NSString *indClass = indCreated ? [g_independentWindow className] : @"None";
    NSString *indPtr = indCreated ? [NSString stringWithFormat:@"%p", g_independentWindow] : @"nil";

    char buf[4096] = {0};
    snprintf(buf, sizeof(buf),
             "version=%s|bridge_loaded=YES|window_found=%s|app_ptr=%p|app_activation_policy=%d|app_is_active=%s|main_window_ptr=%s|main_window_class=%s|key_window_ptr=%s|key_window_class=%s|godot_is_key=%s|godot_is_main=%s|independent_window_ptr=%s|independent_window_class=%s|independent_is_created=%s|independent_is_visible=%s|independent_is_key=%s|independent_is_main=%s|macos_keydown_count=%llu|macos_last_keycode=%d|macos_last_char_count=%d|event_window_class=%s|registered_types=%s",
             NATIVE_DRAG_BRIDGE_VERSION_STR,
             mainWin ? "YES" : "NO",
             NSApp,
             (int)[NSApp activationPolicy],
             [NSApp isActive] ? "YES" : "NO",
             [mainPtr UTF8String],
             [mainClass UTF8String],
             [keyPtr UTF8String],
             [keyClass UTF8String],
             godotIsKey ? "YES" : "NO",
             godotIsMain ? "YES" : "NO",
             [indPtr UTF8String],
             [indClass UTF8String],
             indCreated ? "YES" : "NO",
             indVisible ? "YES" : "NO",
             indIsKey ? "YES" : "NO",
             indIsMain ? "YES" : "NO",
             (unsigned long long)g_macos_keydown_count,
             g_macos_last_keycode,
             g_macos_last_char_count,
             g_macos_event_win_class.c_str(),
             g_diag_info.registered_types.c_str()
    );
    
    if (r_return && conv_to_string && p_string_new_utf8) {
        uint8_t godot_str[64] = {0};
        p_string_new_utf8(godot_str, buf, strlen(buf));
        conv_to_string(r_return, godot_str);
    }
}

static void call_cleanup_native(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    runOnMainThread(^{
        mac_wkwebview_cleanup_native();
    });
}

static void call_test_native_bridge(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt arg_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    queue_external_event({
        "EXTERNAL_SELF_TEST",
        "public.url",
        "https://www.youtube.com/watch?v=SELF_TEST_VERIFIED",
        100.0f,
        100.0f,
        1280.0f,
        800.0f
    });
    
    NSLog(@"[NATIVE_LOG] NATIVE BRIDGE SELF TEST TRIGGERED");
    
    if (r_return && conv_to_bool) {
        int64_t val = 1;
        conv_to_bool(r_return, &val);
    }
}

static void register_method_helper(GDExtensionClassLibraryPtr p_library, const char* class_name, const char* method_name, GDExtensionClassMethodCall call_func, bool has_return) {

    if (!p_register_method || !p_string_name_new) return;
    char class_name_buf[64] = {0};
    char method_name_buf[64] = {0};
    p_string_name_new(class_name_buf, class_name);
    p_string_name_new(method_name_buf, method_name);

    char empty_name[64] = {0};
    char empty_class[64] = {0};
    char empty_hint[64] = {0};
    p_string_name_new(empty_name, "");
    p_string_name_new(empty_class, "");
    if (p_string_new_utf8) {
        p_string_new_utf8(empty_hint, "", 0);
    }

    GDExtensionPropertyInfo ret_info = {};
    ret_info.type = GDEXTENSION_VARIANT_TYPE_INT;
    ret_info.name = empty_name;
    ret_info.class_name = empty_class;
    ret_info.hint = 0;
    ret_info.hint_string = empty_hint;
    ret_info.usage = 6;

    GDExtensionClassMethodInfo minfo = {};
    minfo.name = method_name_buf;
    minfo.method_userdata = nullptr;
    minfo.call_func = call_func;
    minfo.ptrcall_func = nullptr;
    minfo.method_flags = 1; // GDEXTENSION_METHOD_FLAGS_DEFAULT
    minfo.has_return_value = has_return;
    minfo.return_value_info = has_return ? &ret_info : nullptr;
    minfo.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    minfo.argument_count = 0;
    minfo.arguments_info = nullptr;
    minfo.arguments_metadata = nullptr;

    p_register_method(p_library, class_name_buf, &minfo);
}

static GDExtensionInterfaceObjectSetInstance p_object_set_instance = nullptr;

static GDExtensionObjectPtr create_helper_instance(void *p_userdata, GDExtensionBool p_notify) {
    if (p_construct_object && p_string_name_new && p_object_set_instance) {
        char obj_buf[64] = {0};
        char class_buf[64] = {0};
        p_string_name_new(obj_buf, "Object");
        p_string_name_new(class_buf, "MacWKWebViewHelper");
        
        GDExtensionObjectPtr obj = p_construct_object(obj_buf);
        if (obj) {
            p_object_set_instance(obj, class_buf, obj);
        }
        return obj;
    }
    return nullptr;
}

static void free_helper_instance(void *p_userdata, GDExtensionClassInstancePtr p_instance) {
}

static GDExtensionClassLibraryPtr g_library = nullptr;

static void initialize_mac_wkwebview_module(void *p_userdata, GDExtensionInitializationLevel p_level) {
    NSLog(@"[MAC_WKWEBVIEW_INIT] initialize_mac_wkwebview_module level=%d scene_level=%d", (int)p_level, (int)GDEXTENSION_INITIALIZATION_SCENE);
    if (p_level != GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
    
    NSLog(@"[MAC_WKWEBVIEW_INIT] Registering class MacWKWebViewHelper... p_register_class=%p p_string_name_new=%p", p_register_class, p_string_name_new);
    if (p_register_class && p_string_name_new) {
        char class_sn[64] = {0};
        char parent_sn[64] = {0};
        p_string_name_new(class_sn, "MacWKWebViewHelper");
        p_string_name_new(parent_sn, "Object");
        NSLog(@"[MAC_WKWEBVIEW_INIT] Created StringName for class and parent.");
        
        GDExtensionClassCreationInfo6 class_info = {};
        class_info.is_virtual = false;
        class_info.is_abstract = false;
        class_info.is_exposed = true;
        class_info.create_instance_func = create_helper_instance;
        class_info.free_instance_func = free_helper_instance;
        
        NSLog(@"[MAC_WKWEBVIEW_INIT] Calling p_register_class...");
        p_register_class(g_library, class_sn, parent_sn, &class_info);
        NSLog(@"[MAC_WKWEBVIEW_INIT] p_register_class finished!");

        register_method_helper(g_library, "MacWKWebViewHelper", "createPlayer", call_create_player, true);
        register_method_helper(g_library, "MacWKWebViewHelper", "create_player", call_create_player, true);

        register_method_helper(g_library, "MacWKWebViewHelper", "loadVideo", call_load_video, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "load_video", call_load_video, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "playVideo", call_play_video, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "play_video", call_play_video, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "pauseVideo", call_pause_video, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "pause_video", call_pause_video, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "stopVideo", call_stop_video, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "stop_video", call_stop_video, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "setBounds", call_set_bounds, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "set_bounds", call_set_bounds, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "setVisible", call_set_visible, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "set_visible", call_set_visible, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "destroyPlayer", call_destroy_player, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "destroy_player", call_destroy_player, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "pollEvent", call_poll_event, true);
        register_method_helper(g_library, "MacWKWebViewHelper", "poll_event", call_poll_event, true);

        register_method_helper(g_library, "MacWKWebViewHelper", "enableExternalDrag", call_enable_external_drag, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "enable_external_drag", call_enable_external_drag, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "setDragBoxVisible", call_set_drag_box_visible, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "set_drag_box_visible", call_set_drag_box_visible, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "cleanupNative", call_cleanup_native, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "cleanup_native", call_cleanup_native, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "updateTargetPlaylist", call_update_target_playlist, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "update_target_playlist", call_update_target_playlist, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "updateDropStatus", call_update_drop_status, false);
        register_method_helper(g_library, "MacWKWebViewHelper", "update_drop_status", call_update_drop_status, false);

        register_method_helper(g_library, "MacWKWebViewHelper", "pollExternalDrop", call_poll_external_drop, true);
        register_method_helper(g_library, "MacWKWebViewHelper", "poll_external_drop", call_poll_external_drop, true);

        register_method_helper(g_library, "MacWKWebViewHelper", "getNativeDiagnostics", call_get_native_diagnostics, true);
        register_method_helper(g_library, "MacWKWebViewHelper", "get_native_diagnostics", call_get_native_diagnostics, true);

        register_method_helper(g_library, "MacWKWebViewHelper", "testNativeBridge", call_test_native_bridge, true);
        register_method_helper(g_library, "MacWKWebViewHelper", "test_native_bridge", call_test_native_bridge, true);

        NSLog(@"[MAC_WKWEBVIEW_INIT] All methods registered!");

    }
}




static void deinitialize_mac_wkwebview_module(void *p_userdata, GDExtensionInitializationLevel p_level) {
    if (p_level != GDEXTENSION_INITIALIZATION_SCENE) {
        return;
    }
}

GDExtensionBool mac_wkwebview_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    g_library = p_library;
    r_initialization->initialize = initialize_mac_wkwebview_module;
    r_initialization->deinitialize = deinitialize_mac_wkwebview_module;
    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    
    p_string_name_new = (GDExtensionInterfaceStringNameNewWithUtf8Chars)p_get_proc_address("string_name_new_with_utf8_chars");
    p_register_class = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class6");
    if (!p_register_class) p_register_class = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class5");
    if (!p_register_class) p_register_class = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class4");
    if (!p_register_class) p_register_class = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class3");
    if (!p_register_class) p_register_class = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class2");
    if (!p_register_class) p_register_class = (GDExtensionInterfaceClassdbRegisterExtensionClass6)p_get_proc_address("classdb_register_extension_class");

    p_register_method = (GDExtensionInterfaceClassdbRegisterExtensionClassMethod)p_get_proc_address("classdb_register_extension_class_method");
    p_construct_object = (GDExtensionInterfaceClassdbConstructObject3)p_get_proc_address("classdb_construct_object3");
    if (!p_construct_object) p_construct_object = (GDExtensionInterfaceClassdbConstructObject3)p_get_proc_address("classdb_construct_object2");
    if (!p_construct_object) p_construct_object = (GDExtensionInterfaceClassdbConstructObject3)p_get_proc_address("classdb_construct_object");
    p_object_set_instance = (GDExtensionInterfaceObjectSetInstance)p_get_proc_address("object_set_instance");

    
    p_get_variant_to_type = (GDExtensionInterfaceGetVariantToTypeConstructor)p_get_proc_address("get_variant_to_type_constructor");
    p_get_variant_from_type = (GDExtensionInterfaceGetVariantFromTypeConstructor)p_get_proc_address("get_variant_from_type_constructor");
    p_string_to_utf8 = (GDExtensionInterfaceStringToUtf8Chars)p_get_proc_address("string_to_utf8_chars");
    p_string_new_utf8 = (GDExtensionInterfaceStringNewWithUtf8Func)p_get_proc_address("string_new_with_utf8_chars_and_len2");
    if (!p_string_new_utf8) {
        p_string_new_utf8 = (GDExtensionInterfaceStringNewWithUtf8Func)p_get_proc_address("string_new_with_utf8_chars_and_len");
    }

    if (p_get_variant_to_type) {
        conv_from_int = p_get_variant_to_type(GDEXTENSION_VARIANT_TYPE_INT);
        conv_from_float = p_get_variant_to_type(GDEXTENSION_VARIANT_TYPE_FLOAT);
        conv_from_bool = p_get_variant_to_type(GDEXTENSION_VARIANT_TYPE_BOOL);
        conv_from_string = p_get_variant_to_type(GDEXTENSION_VARIANT_TYPE_STRING);
    }
    if (p_get_variant_from_type) {
        conv_to_int = p_get_variant_from_type(GDEXTENSION_VARIANT_TYPE_INT);
        conv_to_string = p_get_variant_from_type(GDEXTENSION_VARIANT_TYPE_STRING);
        conv_to_bool = p_get_variant_from_type(GDEXTENSION_VARIANT_TYPE_BOOL);
    }
    
    return 1;
}

} // extern "C"



