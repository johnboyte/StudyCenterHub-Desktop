class_name MacWKWebViewPlayer
extends Control

## Native macOS WKWebView Player Control for YouTube Playback
## Integrates Apple's WebKit.framework WKWebView with YouTube IFrame Player API.

const NativePlayerBridgeScript = preload("res://src/infrastructure/native/native_player_bridge.gd")

signal player_ready
signal player_playing
signal player_paused
signal player_ended
signal player_error(error_code: int)

var _handle: int = 0
var _is_macos: bool = false
var _is_headless: bool = false
var _loaded_video_id: String = ""
var _is_initialized: bool = false

# Mock state for headless automated unit tests
var _mock_state: String = "IDLE"

func _ready() -> void:
	_is_macos = OS.get_name() == "macOS"
	_is_headless = DisplayServer.get_name() == "headless"
	custom_minimum_size = Vector2(240, 135)
	clip_contents = true
	resized.connect(_update_native_bounds)
	
	call_deferred("_init_native_player")

func _init_native_player() -> void:
	if _is_initialized:
		return
	_is_initialized = true
	
	var extension_exists = ClassDB.class_exists("MacWKWebViewHelper")
	print("[NATIVE_EXTENSION_AVAILABLE] class=MacWKWebViewHelper exists=", extension_exists)
	
	if _is_headless or not _is_macos:
		_mock_state = "READY"
		player_ready.emit()
		return

	var view_handle = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_VIEW)
	if view_handle == 0:
		view_handle = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)

	var pos = global_position
	var sz = size
	if pos.x < 0 or pos.y < 0:
		pos = Vector2(1260.0, 680.0)
	if sz.x <= 50 or sz.y <= 50:
		sz = Vector2(320.0, 180.0)

	print("[WKWEBVIEW_CREATE_REQUEST] view_handle=", view_handle, " pos=", pos, " sz=", sz)
	_handle = NativePlayerBridgeScript.create_player(view_handle, pos.x, pos.y, sz.x, sz.y)
	print("[WKWEBVIEW_CREATE_RESULT] handle=", _handle)
	set_process(true)

func load_video(video_id: String) -> void:
	_loaded_video_id = video_id
	print("[MAC_PLAYER_LOAD_VIDEO_RECEIVED] video_id=", video_id, " native_helper_valid=", (_handle != 0))
	print("[PLAYBACK_SERVICE_START] load_video video_id=", video_id, " handle=", _handle)
	if _is_headless or not _is_macos or _handle == 0:
		_mock_state = "PLAYING"
		player_playing.emit()
		return

	NativePlayerBridgeScript.load_video(_handle, video_id)
	NativePlayerBridgeScript.play_video(_handle)

func play_video() -> void:
	if _is_headless or not _is_macos or _handle == 0:
		_mock_state = "PLAYING"
		player_playing.emit()
		return

	NativePlayerBridgeScript.play_video(_handle)

func pause_video() -> void:
	if _is_headless or not _is_macos or _handle == 0:
		_mock_state = "PAUSED"
		player_paused.emit()
		return

	NativePlayerBridgeScript.pause_video(_handle)

func stop_video() -> void:
	if _is_headless or not _is_macos or _handle == 0:
		_mock_state = "IDLE"
		return

	NativePlayerBridgeScript.stop_video(_handle)

func set_player_visible(visible_flag: bool) -> void:
	visible = visible_flag
	if _handle != 0 and _is_macos and not _is_headless:
		NativePlayerBridgeScript.set_visible(_handle, visible_flag)

func _update_native_bounds() -> void:
	if _handle != 0 and _is_macos and not _is_headless and is_visible_in_tree():
		var pos = global_position
		var sz = size
		if pos.x >= 0 and pos.y >= 0 and sz.x > 50 and sz.y > 50:
			NativePlayerBridgeScript.set_bounds(_handle, pos.x, pos.y, sz.x, sz.y)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_native_bounds()

func _process(_delta: float) -> void:
	if _is_headless or not _is_macos or _handle == 0:
		return

	_update_native_bounds()

	var ev = NativePlayerBridgeScript.poll_event(_handle)
	while ev != null and not ev.is_empty():
		var event_name = str(ev.get("event", ""))
		var event_data = ev.get("data", {})
		if event_data is String:
			var json = JSON.new()
			if json.parse(event_data) == OK:
				event_data = json.get_data()
			else:
				event_data = {}

		match event_name:
			"READY":
				print("[YOUTUBE_IFRAME_API_READY]")
				print("[YT_PLAYER_READY]")
				player_ready.emit()
			"PLAYING":
				print("[YT_STATE_CHANGE] state=PLAYING")
				player_playing.emit()
			"PAUSED":
				print("[YT_STATE_CHANGE] state=PAUSED")
				player_paused.emit()
			"ENDED":
				print("[YT_STATE_CHANGE] state=ENDED")
				player_ended.emit()
			"ERROR":
				var err_code = int(event_data.get("code", 153))
				print("[PLAYBACK_FAILURE] stage=YOUTUBE_IFRAME_ERROR code=", err_code)
				player_error.emit(err_code)

		ev = NativePlayerBridgeScript.poll_event(_handle)

func _exit_tree() -> void:
	if _handle != 0 and _is_macos and not _is_headless:
		NativePlayerBridgeScript.destroy_player(_handle)
		_handle = 0
