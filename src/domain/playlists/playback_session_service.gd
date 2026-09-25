extends RefCounted

## App-Level Media Playback Session & Queue Controller
## Manages media playback queues, persistent session state, repeat modes,
## and cross-view navigation continuity for StudyCenterHub Next Generation.
## Integrates persistent native macOS WKWebView player for in-app YouTube playback.

signal playback_started(item: Dictionary, queue_index: int)
signal playback_paused()
signal playback_resumed()
signal playback_stopped()
signal playback_progress_updated(elapsed: float, duration: float)
signal queue_updated(queue: Array, current_index: int)
signal repeat_mode_changed(mode: String) # "off", "all", "one"
signal unsupported_item_encountered(item: Dictionary)
signal playback_error_occurred(item: Dictionary, error_code: int)

var active_playlist_id: String = ""
var active_playlist_name: String = ""
var queue: Array = []
var current_queue_index: int = -1
var playback_state: String = "stopped" # "stopped", "playing", "paused", "error"
var repeat_mode: String = "off" # "off", "all", "one"

var elapsed_time: float = 0.0
var duration: float = 0.0
var volume: float = 1.0
var is_muted: bool = false

var has_playback_error: bool = false
var last_playback_error_code: int = 0

var _progress_timer_active: bool = false
var native_player: Node = null # MacWKWebViewPlayer instance

func attach_native_player(player_node: Node) -> void:
	native_player = player_node
	if native_player:
		if not native_player.player_ready.is_connected(_on_native_player_ready):
			native_player.player_ready.connect(_on_native_player_ready)
		if not native_player.player_playing.is_connected(_on_native_player_playing):
			native_player.player_playing.connect(_on_native_player_playing)
		if not native_player.player_paused.is_connected(_on_native_player_paused):
			native_player.player_paused.connect(_on_native_player_paused)
		if not native_player.player_ended.is_connected(_on_native_player_ended):
			native_player.player_ended.connect(_on_native_player_ended)
		if not native_player.player_error.is_connected(_on_native_player_error):
			native_player.player_error.connect(_on_native_player_error)

func start_playlist(playlist_name: String, items: Array, start_index: int = 0, playlist_id: String = "") -> void:
	active_playlist_id = playlist_id
	active_playlist_name = playlist_name
	queue = items.duplicate(true)
	current_queue_index = clampi(start_index, 0, max(0, queue.size() - 1))
	queue_updated.emit(queue, current_queue_index)
	
	if queue.size() > 0:
		var item = queue[current_queue_index]
		var vid_id = _extract_youtube_id(str(item.get("url", "")))
		print("[PLAYBACK_START_RECEIVED] service_instance_id=", get_instance_id(), " queue_count=", queue.size(), " current_index=", current_queue_index, " video_id=", vid_id)
		play_item_at_index(current_queue_index)

func play_item_at_index(index: int) -> void:
	if index < 0 or index >= queue.size():
		stop()
		return
		
	current_queue_index = index
	var item = queue[current_queue_index]
	elapsed_time = 0.0
	duration = float(item.get("duration_seconds", 0))
	if duration <= 0.0:
		duration = 210.0 # Default 3:30 fallback duration if unparsed
		
	has_playback_error = false
	last_playback_error_code = 0
	playback_state = "playing"
	playback_started.emit(item, current_queue_index)
	queue_updated.emit(queue, current_queue_index)
	
	print("[PLAYER_INSTANCE] playback_service_id=", get_instance_id(), " mac_wkwebview_player_id=", (native_player.get_instance_id() if native_player else 0), " native_helper_id=", (native_player._handle if (native_player and "_handle" in native_player) else 0), " webview_created=", (native_player._handle != 0 if (native_player and "_handle" in native_player) else false))
	_launch_media_player_for_item(item)
	_start_progress_clock()

func _launch_media_player_for_item(item: Dictionary) -> void:
	var raw_url = str(item.get("url", "")).strip_edges()
	var vid_id = _extract_youtube_id(raw_url)
	print("[REAL_LOAD_VIDEO] video_id=", vid_id, " player_instance_id=", (native_player.get_instance_id() if native_player else 0))
	
	if vid_id != "" and native_player != null:
		native_player.load_video(vid_id)
	elif native_player != null and raw_url != "":
		native_player.load_video(raw_url)
	else:
		print("[PLAYBACK_FAILURE] native_player is NULL in PlaybackSessionService!")
		unsupported_item_encountered.emit(item)

func open_current_in_safari() -> void:
	var item = get_current_item()
	if item.is_empty(): return
	var raw_url = str(item.get("url", "")).strip_edges()
	if raw_url != "":
		OS.shell_open(raw_url)

func _extract_youtube_id(url_str: String) -> String:
	var clean_str = url_str.strip_edges()
	if clean_str.length() == 11 and not "/" in clean_str and not ":" in clean_str:
		return clean_str
	if "v=" in clean_str:
		var parts = clean_str.split("v=")
		if parts.size() > 1:
			var id_part = parts[1].split("&")[0].split("?")[0].split("#")[0]
			if id_part.length() >= 11:
				return id_part.left(11)
	if "youtu.be/" in clean_str:
		var parts = clean_str.split("youtu.be/")
		if parts.size() > 1:
			var id_part = parts[1].split("&")[0].split("?")[0].split("#")[0]
			if id_part.length() >= 11:
				return id_part.left(11)
	if "embed/" in clean_str:
		var parts = clean_str.split("embed/")
		if parts.size() > 1:
			var id_part = parts[1].split("&")[0].split("?")[0].split("#")[0]
			if id_part.length() >= 11:
				return id_part.left(11)
	var regex = RegEx.new()
	regex.compile("[a-zA-Z0-9_-]{11}")
	var result = regex.search(clean_str)
	if result:
		return result.get_string()
	return clean_str

func toggle_play_pause() -> void:
	if playback_state == "playing":
		pause()
	elif playback_state == "paused":
		resume()
	elif playback_state == "stopped" and queue.size() > 0:
		play_item_at_index(0 if current_queue_index < 0 else current_queue_index)

func pause() -> void:
	if playback_state == "playing":
		playback_state = "paused"
		_progress_timer_active = false
		if native_player:
			native_player.pause_video()
		playback_paused.emit()

func resume() -> void:
	if playback_state == "paused":
		playback_state = "playing"
		if native_player:
			native_player.play_video()
		playback_resumed.emit()
		_start_progress_clock()

func stop() -> void:
	playback_state = "stopped"
	_progress_timer_active = false
	elapsed_time = 0.0
	if native_player:
		native_player.stop_video()
	playback_stopped.emit()

func next_song() -> void:
	if queue.size() == 0: return
	if repeat_mode == "one":
		play_item_at_index(current_queue_index)
	elif current_queue_index < queue.size() - 1:
		play_item_at_index(current_queue_index + 1)
	elif repeat_mode == "all":
		play_item_at_index(0)
	else:
		stop()

func previous_song() -> void:
	if queue.size() == 0: return
	if elapsed_time > 4.0:
		seek_to(0.0)
	elif current_queue_index > 0:
		play_item_at_index(current_queue_index - 1)
	elif repeat_mode == "all":
		play_item_at_index(queue.size() - 1)
	else:
		seek_to(0.0)

func seek_to(pos_sec: float) -> void:
	elapsed_time = clampf(pos_sec, 0.0, duration)
	playback_progress_updated.emit(elapsed_time, duration)

func set_repeat_mode(mode: String) -> void:
	if mode in ["off", "all", "one"]:
		repeat_mode = mode
		repeat_mode_changed.emit(repeat_mode)

func cycle_repeat_mode() -> String:
	match repeat_mode:
		"off": set_repeat_mode("all")
		"all": set_repeat_mode("one")
		"one": set_repeat_mode("off")
		_: set_repeat_mode("off")
	return repeat_mode

func get_current_item() -> Dictionary:
	if current_queue_index >= 0 and current_queue_index < queue.size():
		return queue[current_queue_index]
	return {}

func add_playlist_to_queue(items: Array) -> void:
	for it in items:
		queue.append(it.duplicate(true))
	queue_updated.emit(queue, current_queue_index)

func clear_queue() -> void:
	stop()
	queue.clear()
	current_queue_index = -1
	active_playlist_id = ""
	active_playlist_name = ""
	queue_updated.emit(queue, current_queue_index)

func _start_progress_clock() -> void:
	if _progress_timer_active: return
	_progress_timer_active = true
	_tick_progress()

func _tick_progress() -> void:
	if not _progress_timer_active or playback_state != "playing":
		return
	
	elapsed_time += 1.0
	playback_progress_updated.emit(elapsed_time, duration)
	
	# If native player is attached, actual YT.PlayerState.ENDED callback drives next_song()
	# Fallback timer if no native player
	if native_player == null and elapsed_time >= duration:
		_progress_timer_active = false
		next_song()
	else:
		var tree = Engine.get_main_loop() as SceneTree
		if tree:
			tree.create_timer(1.0).timeout.connect(_tick_progress)

# Native player callback handlers
func _on_native_player_ready() -> void:
	var item = get_current_item()
	if not item.is_empty() and playback_state == "playing":
		_launch_media_player_for_item(item)

func _on_native_player_playing() -> void:
	playback_state = "playing"
	has_playback_error = false
	playback_resumed.emit()

func _on_native_player_paused() -> void:
	playback_state = "paused"
	playback_paused.emit()

func _on_native_player_ended() -> void:
	next_song()

func _on_native_player_error(code: int) -> void:
	has_playback_error = true
	last_playback_error_code = code
	playback_state = "error"
	_progress_timer_active = false
	playback_error_occurred.emit(get_current_item(), code)
	
	var tree = Engine.get_main_loop() as SceneTree
	if tree and current_queue_index < queue.size() - 1:
		tree.create_timer(2.5).timeout.connect(func():
			if playback_state == "error":
				next_song()
		)

