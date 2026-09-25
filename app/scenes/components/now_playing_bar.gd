extends PanelContainer

## Persistent Now Playing Bar for StudyCenterHub Desktop AppShell
## Displays active song metadata, playback progress, playback controls, repeat mode,
## volume, queue access, and clean error handling.

var playback_svc: RefCounted

var thumb_rect: TextureRect
var title_lbl: Label
var artist_lbl: Label
var queue_lbl: Label

var btn_prev: Button
var btn_play_pause: Button
var btn_next: Button

var time_lbl: Label
var progress_slider: Slider

var btn_repeat: Button
var btn_queue: Button
var btn_open_youtube: Button

var _thumb_http: HTTPRequest
var _current_thumb_url: String = ""

func _init() -> void:
	_build_ui()

func _ready() -> void:
	visible = false
	_thumb_http = HTTPRequest.new()
	_thumb_http.timeout = 5.0
	add_child(_thumb_http)

func setup_playback_service(svc: RefCounted) -> void:
	playback_svc = svc
	if not playback_svc: return

	playback_svc.playback_started.connect(_on_playback_started)
	playback_svc.playback_paused.connect(_on_playback_paused)
	playback_svc.playback_resumed.connect(_on_playback_resumed)
	playback_svc.playback_stopped.connect(_on_playback_stopped)
	playback_svc.playback_progress_updated.connect(_on_progress_updated)
	playback_svc.queue_updated.connect(_on_queue_updated)
	playback_svc.repeat_mode_changed.connect(_on_repeat_mode_changed)
	if playback_svc.has_signal("playback_error_occurred"):
		playback_svc.playback_error_occurred.connect(_on_playback_error)

	if playback_svc.playback_state != "stopped" and playback_svc.queue.size() > 0:
		visible = true
		_on_playback_started(playback_svc.get_current_item(), playback_svc.current_queue_index)

func _build_ui() -> void:
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	st.border_width_top = 2
	st.border_color = Color(0.85, 0.88, 0.92, 1.0)
	st.content_margin_left = 16
	st.content_margin_top = 8
	st.content_margin_right = 16
	st.content_margin_bottom = 8
	st.shadow_color = Color(0, 0, 0, 0.1)
	st.shadow_size = 6
	st.shadow_offset = Vector2(0, -2)
	add_theme_stylebox_override("panel", st)

	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 16)

	# 1. Thumbnail + Title/Artist Info
	var meta_hbox = HBoxContainer.new()
	meta_hbox.custom_minimum_size = Vector2(260, 0)
	meta_hbox.add_theme_constant_override("separation", 10)

	var thumb_frame = PanelContainer.new()
	thumb_frame.custom_minimum_size = Vector2(56, 36)
	thumb_frame.clip_contents = true
	var tf_st = StyleBoxFlat.new()
	tf_st.bg_color = Color(0.20, 0.45, 0.75, 1.0)
	tf_st.corner_radius_top_left = 4
	tf_st.corner_radius_top_right = 4
	tf_st.corner_radius_bottom_left = 4
	tf_st.corner_radius_bottom_right = 4
	thumb_frame.add_theme_stylebox_override("panel", tf_st)

	thumb_rect = TextureRect.new()
	thumb_rect.custom_minimum_size = Vector2(56, 36)
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb_frame.add_child(thumb_rect)
	meta_hbox.add_child(thumb_frame)

	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	title_lbl = Label.new()
	title_lbl.text = "No Active Song"
	title_lbl.clip_text = true
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	text_vbox.add_child(title_lbl)

	artist_lbl = Label.new()
	artist_lbl.text = ""
	artist_lbl.clip_text = true
	artist_lbl.add_theme_font_size_override("font_size", 11)
	artist_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
	text_vbox.add_child(artist_lbl)

	meta_hbox.add_child(text_vbox)
	main_hbox.add_child(meta_hbox)

	# 2. Controls & Progress (Center)
	var ctrl_vbox = VBoxContainer.new()
	ctrl_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_vbox.add_theme_constant_override("separation", 2)

	var btns_hbox = HBoxContainer.new()
	btns_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btns_hbox.add_theme_constant_override("separation", 10)

	btn_prev = Button.new()
	btn_prev.text = "⏮"
	btn_prev.tooltip_text = "Previous Song"
	btn_prev.custom_minimum_size = Vector2(36, 28)
	btn_prev.pressed.connect(func(): if playback_svc: playback_svc.previous_song())
	btns_hbox.add_child(btn_prev)

	btn_play_pause = Button.new()
	btn_play_pause.text = "▶"
	btn_play_pause.tooltip_text = "Play / Pause"
	btn_play_pause.custom_minimum_size = Vector2(40, 28)
	btn_play_pause.pressed.connect(func(): if playback_svc: playback_svc.toggle_play_pause())
	btns_hbox.add_child(btn_play_pause)

	btn_next = Button.new()
	btn_next.text = "⏭"
	btn_next.tooltip_text = "Next Song"
	btn_next.custom_minimum_size = Vector2(36, 28)
	btn_next.pressed.connect(func(): if playback_svc: playback_svc.next_song())
	btns_hbox.add_child(btn_next)

	ctrl_vbox.add_child(btns_hbox)

	var time_hbox = HBoxContainer.new()
	time_hbox.add_theme_constant_override("separation", 8)

	time_lbl = Label.new()
	time_lbl.text = "0:00 / 0:00"
	time_lbl.add_theme_font_size_override("font_size", 10)
	time_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
	time_hbox.add_child(time_lbl)

	progress_slider = HSlider.new()
	progress_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_slider.min_value = 0.0
	progress_slider.max_value = 100.0
	progress_slider.value = 0.0
	progress_slider.drag_ended.connect(func(value_changed: bool):
		if value_changed and playback_svc:
			playback_svc.seek_to(progress_slider.value)
	)
	time_hbox.add_child(progress_slider)

	ctrl_vbox.add_child(time_hbox)
	main_hbox.add_child(ctrl_vbox)

	# 3. Queue Info & Options (Right)
	var right_hbox = HBoxContainer.new()
	right_hbox.add_theme_constant_override("separation", 8)

	queue_lbl = Label.new()
	queue_lbl.text = "Queue: Default"
	queue_lbl.add_theme_font_size_override("font_size", 11)
	queue_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
	right_hbox.add_child(queue_lbl)

	btn_open_youtube = Button.new()
	btn_open_youtube.text = "🔗 YouTube"
	btn_open_youtube.tooltip_text = "Open on YouTube in external browser"
	btn_open_youtube.custom_minimum_size = Vector2(90, 28)
	btn_open_youtube.pressed.connect(func():
		if playback_svc: playback_svc.open_current_in_safari()
	)
	right_hbox.add_child(btn_open_youtube)

	btn_repeat = Button.new()
	btn_repeat.text = "🔁 Off"
	btn_repeat.tooltip_text = "Repeat Mode: Off (Click to toggle Repeat All / Repeat One)"
	btn_repeat.custom_minimum_size = Vector2(76, 28)
	btn_repeat.pressed.connect(func():
		if playback_svc:
			playback_svc.cycle_repeat_mode()
	)
	right_hbox.add_child(btn_repeat)

	btn_queue = Button.new()
	btn_queue.text = "▴ Queue"
	btn_queue.tooltip_text = "Open Active Queue Window"
	btn_queue.custom_minimum_size = Vector2(76, 28)
	btn_queue.pressed.connect(_show_queue_dialog)
	right_hbox.add_child(btn_queue)

	var btn_expand = Button.new()
	btn_expand.text = "⛶ View"
	btn_expand.tooltip_text = "Expand or collapse native video player"
	btn_expand.custom_minimum_size = Vector2(70, 28)
	btn_expand.pressed.connect(func():
		var app_shell = get_tree().get_first_node_in_group("app_shell")
		if app_shell and app_shell.has_method("toggle_player_expansion"):
			app_shell.toggle_player_expansion()
	)
	right_hbox.add_child(btn_expand)

	main_hbox.add_child(right_hbox)
	add_child(main_hbox)

func _on_playback_started(item: Dictionary, _idx: int) -> void:
	visible = true
	title_lbl.text = str(item.get("title", "Untitled Media"))
	artist_lbl.text = str(item.get("artist", ""))
	btn_play_pause.text = "⏸"

	if playback_svc:
		if playback_svc.active_playlist_name != "":
			queue_lbl.text = "Queue: " + playback_svc.active_playlist_name
		else:
			queue_lbl.text = "Queue (" + str(playback_svc.queue.size()) + " songs)"

	var thumb_url = str(item.get("thumbnail_url", ""))
	if thumb_url != "" and thumb_url != _current_thumb_url:
		_current_thumb_url = thumb_url
		_fetch_thumb(thumb_url)

func _on_playback_paused() -> void:
	btn_play_pause.text = "▶"

func _on_playback_resumed() -> void:
	btn_play_pause.text = "⏸"

func _on_playback_stopped() -> void:
	btn_play_pause.text = "▶"
	time_lbl.text = "0:00 / 0:00"
	progress_slider.value = 0.0

func _on_playback_error(item: Dictionary, err_code: int) -> void:
	btn_play_pause.text = "▶"
	var item_title = str(item.get("title", "Selected Video"))
	title_lbl.text = "⚠️ " + item_title
	artist_lbl.text = "This video cannot be played inside StudyCenterHub (YouTube Error " + str(err_code) + ")"
	_show_playback_error_dialog(item_title, err_code)

func _show_playback_error_dialog(item_title: String, err_code: int) -> void:
	var dlg = AcceptDialog.new()
	dlg.title = "Video Cannot Be Embedded"
	dlg.dialog_text = "This video cannot be played inside StudyCenterHub.\n(" + item_title + " - YouTube Error Code " + str(err_code) + ")\n\nWould you like to open it on YouTube or skip to the next song?"
	dlg.ok_button_text = "Open on YouTube"

	var btn_skip = dlg.add_cancel_button("Skip Song")
	btn_skip.pressed.connect(func():
		if playback_svc: playback_svc.next_song()
		dlg.queue_free()
	)
	dlg.confirmed.connect(func():
		if playback_svc: playback_svc.open_current_in_safari()
		dlg.queue_free()
	)
	add_child(dlg)
	dlg.popup_centered(Vector2i(480, 180))

func _on_progress_updated(elapsed: float, dur: float) -> void:
	if dur > 0.0:
		progress_slider.max_value = dur
		progress_slider.value = elapsed
		time_lbl.text = _fmt_time(elapsed) + " / " + _fmt_time(dur)

func _on_queue_updated(queue_arr: Array, _idx: int) -> void:
	if playback_svc:
		if playback_svc.active_playlist_name != "":
			queue_lbl.text = "Queue: " + playback_svc.active_playlist_name
		else:
			queue_lbl.text = "Queue (" + str(queue_arr.size()) + " songs)"

func _on_repeat_mode_changed(mode: String) -> void:
	match mode:
		"off":
			btn_repeat.text = "🔁 Off"
			btn_repeat.tooltip_text = "Repeat Mode: Off (Plays queue once)"
		"all":
			btn_repeat.text = "🔁 All"
			btn_repeat.tooltip_text = "Repeat Mode: Repeat All (Loop queue)"
		"one":
			btn_repeat.text = "🔂 One"
			btn_repeat.tooltip_text = "Repeat Mode: Repeat One (Loop current song)"

func _fetch_thumb(url_str: String) -> void:
	if _thumb_http and _thumb_http.is_inside_tree():
		if _thumb_http.request_completed.is_connected(_on_thumb_downloaded):
			_thumb_http.request_completed.disconnect(_on_thumb_downloaded)
		_thumb_http.request_completed.connect(_on_thumb_downloaded)
		_thumb_http.request(url_str)

func _on_thumb_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 0:
		var img = Image.new()
		var err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_png_from_buffer(body)
		if err == OK:
			var tex = ImageTexture.create_from_image(img)
			if thumb_rect:
				thumb_rect.texture = tex

func _fmt_time(sec: float) -> String:
	var total = int(sec)
	var m = total / 60
	var s = total % 60
	return "%d:%02d" % [m, s]

func _show_queue_dialog() -> void:
	if not playback_svc: return
	var dlg = AcceptDialog.new()
	dlg.title = "Active Queue — " + (playback_svc.active_playlist_name if playback_svc.active_playlist_name != "" else "Custom Queue")
	dlg.size = Vector2i(500, 400)
	
	var vbox = VBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "Queued Items (" + str(playback_svc.queue.size()) + "):"
	vbox.add_child(lbl)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 300)
	var item_vbox = VBoxContainer.new()
	
	for i in range(playback_svc.queue.size()):
		var it = playback_svc.queue[i]
		var hb = HBoxContainer.new()
		var p_lbl = Label.new()
		if i == playback_svc.current_queue_index:
			p_lbl.text = "▶ " + str(i + 1) + ". " + str(it.get("title", "")) + " (Now Playing)"
			p_lbl.add_theme_color_override("font_color", Color(0.20, 0.45, 0.75, 1.0))
		else:
			p_lbl.text = "   " + str(i + 1) + ". " + str(it.get("title", ""))
		hb.add_child(p_lbl)
		item_vbox.add_child(hb)
		
	scroll.add_child(item_vbox)
	vbox.add_child(scroll)
	dlg.add_child(vbox)
	
	dlg.close_requested.connect(func(): dlg.queue_free())
	dlg.confirmed.connect(func(): dlg.queue_free())
	
	var parent_win = get_viewport()
	if parent_win:
		parent_win.add_child(dlg)
		dlg.popup_centered()
