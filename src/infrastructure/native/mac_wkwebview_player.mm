#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#include <mutex>
#include <vector>
#include <string>
#include <cstdlib>
#include <cstring>
#include "gdextension_interface.h"

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
    }
    
    return 1;
}

} // extern "C"



