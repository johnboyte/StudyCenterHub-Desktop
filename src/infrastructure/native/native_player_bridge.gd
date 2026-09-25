class_name NativePlayerBridge
extends Object

## Native macOS WKWebView Player Bridge
## Invokes Objective-C / WebKit methods on macOS desktop and provides mock fallbacks for headless testing.

static func create_player(view_handle: int, x: float, y: float, w: float, h: float) -> int:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless":
		return 1 # Mock handle for tests
		
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			var res = helper.call("createPlayer", view_handle, x, y, w, h)
			print("[NATIVE_BRIDGE] helper.call('createPlayer') returned=", res)
			if res != null and int(res) != 0:
				return int(res)
				
	print("[NATIVE_BRIDGE] Fallback to mock handle 1")
	return 1

static func load_video(handle: int, video_id: String) -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			helper.call("loadVideo", handle, video_id)

static func play_video(handle: int) -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			helper.call("playVideo", handle)

static func pause_video(handle: int) -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			helper.call("pauseVideo", handle)

static func stop_video(handle: int) -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			helper.call("stopVideo", handle)

static func set_bounds(handle: int, x: float, y: float, w: float, h: float) -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			helper.call("setBounds", handle, x, y, w, h)

static func set_visible(handle: int, visible: bool) -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			helper.call("setVisible", handle, visible)

static func destroy_player(handle: int) -> void:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			helper.call("destroyPlayer", handle)

static func poll_event(handle: int) -> Dictionary:
	if OS.get_name() != "macOS" or DisplayServer.get_name() == "headless" or handle == 0:
		return {}
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		if helper:
			var res = helper.call("pollEvent", handle)
			if res is Dictionary:
				return res
			elif res is String and res != "":
				var parts = res.split("|", true, 1)
				return {
					"event": parts[0],
					"data": parts[1] if parts.size() > 1 else "{}"
				}
	return {}


