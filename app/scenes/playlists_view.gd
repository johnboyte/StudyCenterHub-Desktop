extends Control

## Playlists Subsystem Workspace View
## Features robust select-and-drag reordering with force_drag(),
## full-workspace URL drag-and-drop from Safari/Chrome with visual insertion indicators,
## 1-click "📋 Paste URL" button & Cmd+V shortcut, uncluttered song row UI with options menu (⋮),
## confirmation-backed item removal, keyboard Delete/Backspace removal, duplicate video ID detection,
## and keyless oEmbed YouTube metadata fetching.

const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")

var db: RefCounted
var playlists_svc: RefCounted

var current_playlist_id: String = ""
var selected_song_item_id: String = ""
var playlists_list: Array = []
var items_list: Array = []

@onready var sidebar_panel: PanelContainer = $MainMargin/WorkspaceHBox/LibrarySidebarPanel
@onready var btn_new_playlist: Button = $MainMargin/WorkspaceHBox/LibrarySidebarPanel/SidebarMargin/SidebarVBox/SidebarHeaderHBox/BtnNewPlaylist
@onready var search_library_input: LineEdit = $MainMargin/WorkspaceHBox/LibrarySidebarPanel/SidebarMargin/SidebarVBox/SearchLibraryInput
@onready var playlists_vbox: VBoxContainer = $MainMargin/WorkspaceHBox/LibrarySidebarPanel/SidebarMargin/SidebarVBox/PlaylistsScroll/PlaylistsVBox

@onready var detail_panel: PanelContainer = $MainMargin/WorkspaceHBox/DetailWorkspacePanel
@onready var detail_vbox: VBoxContainer = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox
@onready var selected_playlist_title: Label = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderTopHBox/TitleVBox/SelectedPlaylistTitle
@onready var selected_playlist_meta: Label = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderTopHBox/TitleVBox/SelectedPlaylistMeta
@onready var header_actions_hbox: HBoxContainer = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderActionsHBox

@onready var btn_add_media: Button = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderActionsHBox/BtnAddMedia
@onready var btn_search_youtube: Button = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderActionsHBox/BtnSearchYouTube
@onready var btn_duplicate_playlist: Button = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderTopHBox/PlaylistMgmtHBox/BtnDuplicatePlaylist
@onready var btn_edit_playlist: Button = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderTopHBox/PlaylistMgmtHBox/BtnEditPlaylist
@onready var btn_delete_playlist: Button = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderTopHBox/PlaylistMgmtHBox/BtnDeletePlaylist
var btn_paste_url: Button

var btn_play_playlist: Button
var quick_add_url_input: LineEdit
var _last_detected_clip_url: String = ""
var clipboard_banner_panel: PanelContainer

@onready var item_search_input: LineEdit = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/ItemSearchInput
@onready var items_vbox: VBoxContainer = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/ItemsScroll/ItemsVBox

var _http_fetcher: HTTPRequest
var _yt_search_http: HTTPRequest
var playback_svc: RefCounted

func _ready() -> void:
	_set_container_mouse_filters_pass()
	_setup_header_actions()
	_apply_input_and_button_rules()
	_init_services()
	_connect_signals()

	_http_fetcher = HTTPRequest.new()
	_http_fetcher.timeout = 6.0
	add_child(_http_fetcher)

	_yt_search_http = HTTPRequest.new()
	_yt_search_http.timeout = 8.0
	add_child(_yt_search_http)

	var win = get_window()
	if win:
		if not win.files_dropped.is_connected(_on_files_dropped):
			win.files_dropped.connect(_on_files_dropped)
		if not win.focus_entered.is_connected(_check_clipboard_on_focus):
			win.focus_entered.connect(_check_clipboard_on_focus)


	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CAN_DROP

	load_playlists()

func _set_container_mouse_filters_pass() -> void:
	var containers = [
		$MainMargin,
		$MainMargin/WorkspaceHBox,
		sidebar_panel,
		$MainMargin/WorkspaceHBox/LibrarySidebarPanel/SidebarMargin,
		$MainMargin/WorkspaceHBox/LibrarySidebarPanel/SidebarMargin/SidebarVBox,
		playlists_vbox,
		$MainMargin/WorkspaceHBox/LibrarySidebarPanel/SidebarMargin/SidebarVBox/PlaylistsScroll,
		detail_panel,
		$MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin,
		$MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox,
		items_vbox,
		$MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/ItemsScroll
	]
	for c in containers:
		if c:
			c.mouse_filter = Control.MOUSE_FILTER_PASS

func _setup_header_actions() -> void:
	if header_actions_hbox:
		btn_play_playlist = Button.new()
		btn_play_playlist.text = "▶ Play Playlist"
		btn_play_playlist.tooltip_text = "Start playing this playlist from song #1"
		_style_button(btn_play_playlist, true)
		btn_play_playlist.pressed.connect(_on_play_playlist_pressed)
		header_actions_hbox.add_child(btn_play_playlist)
		header_actions_hbox.move_child(btn_play_playlist, 0)

		quick_add_url_input = LineEdit.new()
		quick_add_url_input.placeholder_text = "🔗 Paste YouTube URL here..."
		quick_add_url_input.tooltip_text = "Copy a YouTube URL in your browser and paste it here to add a song"
		quick_add_url_input.custom_minimum_size = Vector2(240, 32)
		quick_add_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick_add_url_input.caret_blink = true
		quick_add_url_input.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
		quick_add_url_input.text_changed.connect(func(new_text: String):
			_on_quick_url_text_changed(new_text, quick_add_url_input, current_playlist_id, _get_target_insert_index())
		)
		quick_add_url_input.text_submitted.connect(func(new_text: String):
			_on_quick_url_text_submitted(new_text, quick_add_url_input, current_playlist_id, _get_target_insert_index())
		)
		header_actions_hbox.add_child(quick_add_url_input)
		header_actions_hbox.move_child(quick_add_url_input, 1)

		btn_paste_url = Button.new()
		btn_paste_url.text = "📋 Paste URL"
		btn_paste_url.tooltip_text = "Instantly add YouTube or media URL from clipboard"
		_style_button(btn_paste_url)
		btn_paste_url.pressed.connect(_on_paste_url_pressed)
		header_actions_hbox.add_child(btn_paste_url)
		header_actions_hbox.move_child(btn_paste_url, 2)

var click_banner_lbl: Label = null

func show_click_received_banner(song_title: String) -> void:
	if not click_banner_lbl or not is_instance_valid(click_banner_lbl):
		click_banner_lbl = Label.new()
		click_banner_lbl.name = "ClickReceivedBanner"
		click_banner_lbl.add_theme_font_size_override("font_size", 16)
		click_banner_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.12, 0.65, 0.32, 1.0) # Vibrant Green
		st.content_margin_left = 16
		st.content_margin_top = 8
		st.content_margin_right = 16
		st.content_margin_bottom = 8
		st.corner_radius_top_left = 6
		st.corner_radius_top_right = 6
		st.corner_radius_bottom_left = 6
		st.corner_radius_bottom_right = 6
		click_banner_lbl.add_theme_stylebox_override("panel", st)
		if detail_vbox:
			detail_vbox.add_child(click_banner_lbl)
			detail_vbox.move_child(click_banner_lbl, 0)
			
	click_banner_lbl.text = "PLAY CLICK RECEIVED — " + song_title
	click_banner_lbl.visible = true

func _get_playback_service() -> RefCounted:
	if playback_svc != null:
		return playback_svc
	if is_inside_tree():
		var app_shell = get_tree().get_first_node_in_group("app_shell")
		if app_shell and "playback_svc" in app_shell and app_shell.playback_svc != null:
			playback_svc = app_shell.playback_svc
	return playback_svc

func _on_play_playlist_pressed() -> void:
	print("REAL_PLAY_BUTTON_CLICKED")
	if btn_play_playlist:
		btn_play_playlist.text = "CLICK RECEIVED"
	show_click_received_banner("Playlist " + current_playlist_id)

	if not playlists_svc or not db:
		_init_services()
		
	var svc = _get_playback_service()
	print("[REAL_PLAY_CLICK] playlist_id=", current_playlist_id, " item_id=FIRST title=PlayPlaylist url=")
	
	if current_playlist_id.is_empty():
		var all_pl = playlists_svc.get_all_playlists() if playlists_svc else []
		if all_pl.size() > 0:
			current_playlist_id = str(all_pl[0].get("id", ""))
			
	if current_playlist_id.is_empty():
		print("[PLAYBACK_FAILURE] current_playlist_id is empty")
		return
		
	if items_list.size() == 0 and playlists_svc:
		items_list = playlists_svc.get_playlist_items(current_playlist_id)
		
	if items_list.size() == 0:
		print("[PLAYBACK_FAILURE] items_list is empty for playlist_id=", current_playlist_id)
		return
		
	var pl = playlists_svc.get_playlist_by_id(current_playlist_id) if playlists_svc else {}
	var pl_name = str(pl.get("name", "Playlist"))
	var first_url = str(items_list[0].get("url", "")) if items_list.size() > 0 else ""
	var first_vid = playlists_svc.extract_youtube_video_id(first_url) if playlists_svc else ""
	print("[REAL_PLAY_VIDEO_ID] video_id=", first_vid)
	
	if svc:
		print("[REAL_PLAY_SERVICE_CALL] service_instance_id=", svc.get_instance_id(), " playlist_id=", current_playlist_id, " item_index=0 video_id=", first_vid)
		svc.start_playlist(pl_name, items_list, 0, current_playlist_id)
	else:
		print("[PLAYBACK_FAILURE] _get_playback_service() returned NULL!")

func _init_services() -> void:
	if not db:
		var SQLiteDatabaseScript = load("res://src/infrastructure/database/sqlite_database.gd")
		if SQLiteDatabaseScript:
			db = SQLiteDatabaseScript.new()
	if db:
		playlists_svc = PlaylistsServiceScript.new(db)

	_get_playback_service()



func _apply_input_and_button_rules() -> void:
	# Caret rule
	var line_edits = [search_library_input, item_search_input, quick_add_url_input]
	for le in line_edits:
		if le:
			le.caret_blink = true
			le.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))

	# Button hover styling rules
	var btns = [btn_new_playlist, btn_add_media, btn_paste_url, btn_search_youtube, btn_duplicate_playlist, btn_edit_playlist, btn_delete_playlist]
	for b in btns:
		if b:
			_style_button(b)

func _style_button(btn: Button, is_primary: bool = false, is_danger: bool = false) -> void:
	if not btn: return
	var normal_st = StyleBoxFlat.new()
	normal_st.corner_radius_top_left = 6
	normal_st.corner_radius_top_right = 6
	normal_st.corner_radius_bottom_left = 6
	normal_st.corner_radius_bottom_right = 6
	normal_st.content_margin_left = 10
	normal_st.content_margin_right = 10
	normal_st.content_margin_top = 5
	normal_st.content_margin_bottom = 5

	if is_primary:
		normal_st.bg_color = Color(0.596, 0.192, 0.255, 1.0)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	elif is_danger:
		normal_st.bg_color = Color(0.85, 0.22, 0.22, 1.0)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		normal_st.bg_color = Color(0.93, 0.95, 0.97, 1.0)
		btn.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))

	var hover_st = normal_st.duplicate() as StyleBoxFlat
	if is_primary:
		hover_st.bg_color = Color(0.70, 0.23, 0.30, 1.0)
	elif is_danger:
		hover_st.bg_color = Color(0.95, 0.30, 0.30, 1.0)
	else:
		hover_st.bg_color = Color(0.86, 0.89, 0.93, 1.0)

	btn.add_theme_stylebox_override("normal", normal_st)
	btn.add_theme_stylebox_override("hover", hover_st)
	btn.add_theme_stylebox_override("pressed", hover_st)
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.10, 0.15, 1.0) if not (is_primary or is_danger) else Color(1,1,1,1))
	btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.10, 0.15, 1.0) if not (is_primary or is_danger) else Color(1,1,1,1))
	btn.add_theme_color_override("font_focus_color", Color(0.08, 0.10, 0.15, 1.0) if not (is_primary or is_danger) else Color(1,1,1,1))

func _connect_signals() -> void:
	if btn_new_playlist and not btn_new_playlist.pressed.is_connected(_on_create_playlist_pressed):
		btn_new_playlist.pressed.connect(_on_create_playlist_pressed)
	if search_library_input and not search_library_input.text_changed.is_connected(_on_search_library_changed):
		search_library_input.text_changed.connect(_on_search_library_changed)
	if item_search_input and not item_search_input.text_changed.is_connected(_on_search_items_changed):
		item_search_input.text_changed.connect(_on_search_items_changed)

	if btn_add_media and not btn_add_media.pressed.is_connected(_on_add_media_pressed):
		btn_add_media.pressed.connect(_on_add_media_pressed)
	if btn_search_youtube and not btn_search_youtube.pressed.is_connected(_on_search_youtube_pressed):
		btn_search_youtube.pressed.connect(_on_search_youtube_pressed)
	if btn_duplicate_playlist and not btn_duplicate_playlist.pressed.is_connected(_on_duplicate_playlist_pressed):
		btn_duplicate_playlist.pressed.connect(_on_duplicate_playlist_pressed)
	if btn_edit_playlist and not btn_edit_playlist.pressed.is_connected(_on_edit_playlist_pressed):
		btn_edit_playlist.pressed.connect(_on_edit_playlist_pressed)
	if btn_delete_playlist and not btn_delete_playlist.pressed.is_connected(_on_delete_playlist_pressed):
		btn_delete_playlist.pressed.connect(_on_delete_playlist_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.is_command_or_control_pressed() and event.keycode == KEY_V:
			var focus_owner = get_viewport().gui_get_focus_owner()
			if focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is CodeEdit:
				return
			_on_paste_url_pressed()
			get_viewport().set_input_as_handled()

func _on_paste_url_pressed() -> void:
	if current_playlist_id.is_empty(): return
	var clip_text = DisplayServer.clipboard_get().strip_edges()
	if clip_text.is_empty():
		_show_invalid_url_notification("Clipboard is empty.")
		return

	var validation = playlists_svc.validate_and_extract_url(clip_text)
	if not validation["is_valid"]:
		_show_invalid_url_notification("No valid media URL found.")
		return

	_process_dropped_url_or_file(str(validation["canonical_url"]), current_playlist_id, -1)

func _get_target_insert_index() -> int:
	if selected_song_item_id.is_empty():
		return -1
	for i in range(items_list.size()):
		if str(items_list[i].get("id", "")) == selected_song_item_id:
			return i + 1
	return -1

func _on_quick_url_text_changed(new_text: String, input_control: LineEdit, target_playlist_id: String, target_index: int) -> void:
	var clean_text = new_text.strip_edges()
	if clean_text.is_empty():
		return
	if not playlists_svc:
		return
	var validation = playlists_svc.validate_and_extract_url(clean_text)
	if validation["is_valid"]:
		if input_control:
			input_control.text = ""
		_process_dropped_url_or_file(clean_text, target_playlist_id, target_index)

func _on_quick_url_text_submitted(new_text: String, input_control: LineEdit, target_playlist_id: String, target_index: int) -> void:
	var clean_text = new_text.strip_edges()
	if clean_text.is_empty():
		return
	if input_control:
		input_control.text = ""
	_process_dropped_url_or_file(clean_text, target_playlist_id, target_index)

func _check_clipboard_on_focus() -> void:
	if current_playlist_id.is_empty() or not playlists_svc:
		return
	var clip = DisplayServer.clipboard_get().strip_edges()
	if clip.is_empty() or clip == _last_detected_clip_url:
		return

	var val = playlists_svc.validate_and_extract_url(clip)
	if val["is_valid"]:
		_last_detected_clip_url = clip
		_show_clipboard_banner(clip, val)

func _show_clipboard_banner(clip_url: String, meta: Dictionary) -> void:
	if not detail_vbox: return
	if clipboard_banner_panel and is_instance_valid(clipboard_banner_panel):
		clipboard_banner_panel.queue_free()

	clipboard_banner_panel = PanelContainer.new()

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.92, 0.96, 1.0, 1.0)
	st.border_width_left = 4
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.border_color = Color(0.596, 0.192, 0.255, 1.0)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	clipboard_banner_panel.add_theme_stylebox_override("panel", st)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var lbl_info = Label.new()
	var media_title = str(meta.get("title", ""))
	if media_title == "": media_title = clip_url
	lbl_info.text = "📋 YouTube Link Copied: " + media_title
	lbl_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_info.add_theme_font_size_override("font_size", 13)
	lbl_info.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(lbl_info)

	var btn_add = Button.new()
	btn_add.text = "⚡ Add Song to Playlist"
	_style_button(btn_add, true)
	btn_add.pressed.connect(func():
		_process_dropped_url_or_file(clip_url, current_playlist_id, _get_target_insert_index())
		if clipboard_banner_panel and is_instance_valid(clipboard_banner_panel):
			clipboard_banner_panel.queue_free()
	)
	hbox.add_child(btn_add)

	var btn_dismiss = Button.new()
	btn_dismiss.text = "✖"
	btn_dismiss.tooltip_text = "Dismiss notification"
	_style_button(btn_dismiss)
	btn_dismiss.pressed.connect(func():
		if clipboard_banner_panel and is_instance_valid(clipboard_banner_panel):
			clipboard_banner_panel.queue_free()
	)
	hbox.add_child(btn_dismiss)

	clipboard_banner_panel.add_child(hbox)
	detail_vbox.add_child(clipboard_banner_panel)
	detail_vbox.move_child(clipboard_banner_panel, 0)

func _extract_url_from_data(data: Variant) -> String:
	if data == null:
		return ""
	if typeof(data) == TYPE_STRING:
		return str(data).strip_edges()
	elif typeof(data) == TYPE_DICTIONARY:
		var d = data as Dictionary
		for key in ["url", "uri", "text", "path", "link", "value"]:
			if d.has(key) and typeof(d[key]) == TYPE_STRING:
				return str(d[key]).strip_edges()
		for key in ["files", "urls", "items"]:
			if d.has(key):
				var arr = d[key]
				if (typeof(arr) == TYPE_ARRAY or typeof(arr) == TYPE_PACKED_STRING_ARRAY) and arr.size() > 0:
					return str(arr[0]).strip_edges()
		var dict_str = str(d)
		if "http://" in dict_str.to_lower() or "https://" in dict_str.to_lower() or "file://" in dict_str.to_lower():
			return dict_str
	elif typeof(data) == TYPE_PACKED_STRING_ARRAY or typeof(data) == TYPE_ARRAY:
		var arr = data
		if arr.size() > 0:
			return str(arr[0]).strip_edges()

	var fallback_str = str(data).strip_edges()
	if "http://" in fallback_str.to_lower() or "https://" in fallback_str.to_lower() or "file://" in fallback_str.to_lower():
		return fallback_str

	return ""

# ==============================================================================
# FULL WORKSPACE DRAG AND DROP (Root View Handlers)
# ==============================================================================

func set_active_song_drop_slot(slot_index: int) -> void:
	if not items_vbox: return
	for child in items_vbox.get_children():
		if child is SongDropSlotControl:
			child._update_style(child.slot_index == slot_index)

func set_active_playlist_drop_slot(slot_index: int) -> void:
	if not playlists_vbox: return
	for child in playlists_vbox.get_children():
		if child is PlaylistDropSlotControl:
			child._update_style(child.slot_index == slot_index)

func clear_all_drop_slots() -> void:
	if items_vbox:
		for child in items_vbox.get_children():
			if child is SongDropSlotControl:
				child._update_style(false)
	if playlists_vbox:
		for child in playlists_vbox.get_children():
			if child is PlaylistDropSlotControl:
				child._update_style(false)
			elif child is PlaylistCardControl and child.drop_indicator_position != "":
				child.drop_indicator_position = ""
				child._update_style()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not sidebar_panel or not detail_panel:
		return false

	var global_pos = global_position + at_position
	var sb_rect = sidebar_panel.get_global_rect()
	var dt_rect = detail_panel.get_global_rect()

	if sb_rect.has_point(global_pos):
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "song_item":
			clear_all_drop_slots()
			return false
		elif typeof(data) == TYPE_DICTIONARY and data.get("type") == "playlist":
			return true
		else:
			var url_str = _extract_url_from_data(data)
			if url_str != "":
				var val = playlists_svc.validate_and_extract_url(url_str)
				if not val["is_valid"]:
					clear_all_drop_slots()
					return false
			return true
	elif dt_rect.has_point(global_pos):
		if current_playlist_id.is_empty():
			if playlists_list.size() > 0:
				current_playlist_id = str(playlists_list[0].get("id", ""))
			else:
				var res = playlists_svc.create_playlist("My Playlist", "Default playlist for saved media")
				if res["success"]:
					load_playlists(str(res["playlist"]["id"]))

		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "playlist":
			clear_all_drop_slots()
			return false
		if typeof(data) != TYPE_DICTIONARY or not data.has("type"):
			var url_str = _extract_url_from_data(data)
			if url_str != "":
				var val = playlists_svc.validate_and_extract_url(url_str)
				if not val["is_valid"]:
					clear_all_drop_slots()
					return false
		return true

	clear_all_drop_slots()
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	clear_all_drop_slots()
	var global_pos = global_position + at_position

	var sb_rect = sidebar_panel.get_global_rect() if sidebar_panel else Rect2()
	var dt_rect = detail_panel.get_global_rect() if detail_panel else Rect2()

	if sb_rect.has_point(global_pos):
		if typeof(data) != TYPE_DICTIONARY or data.get("type") != "playlist":
			var url_str = _extract_url_from_data(data)
			if url_str == "": url_str = DisplayServer.clipboard_get().strip_edges()
			if url_str != "":
				var target_id = current_playlist_id
				if not target_id.is_empty():
					_process_dropped_url_or_file(url_str, target_id, -1)
	elif dt_rect.has_point(global_pos):
		if current_playlist_id.is_empty():
			return
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "song_item":
			var target_idx = items_list.size()
			var from_index = int(data.get("index", -1))
			if from_index >= 0 and from_index < target_idx:
				target_idx -= 1
			reorder_song_to_index(str(data.get("id", "")), target_idx)
		else:
			var url_str = _extract_url_from_data(data)
			if url_str == "": url_str = DisplayServer.clipboard_get().strip_edges()
			if url_str != "":
				_process_dropped_url_or_file(url_str, current_playlist_id, items_list.size())

func _draw() -> void:
	pass # Structural DropSlot controls replace canvas drawing!

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		clear_all_drop_slots()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_check_clipboard_on_focus()


# ==============================================================================
# PLAYLIST LIBRARY UI (SELECT & DRAG)
# ==============================================================================

func load_playlists(select_id: String = "") -> void:
	if not playlists_svc:
		return
	playlists_list = playlists_svc.get_all_playlists()
	_render_playlists_list()

	if playlists_list.size() > 0:
		var target_id = select_id
		if target_id.is_empty() or not _playlist_exists(target_id):
			if current_playlist_id != "" and _playlist_exists(current_playlist_id):
				target_id = current_playlist_id
			else:
				target_id = str(playlists_list[0].get("id", ""))
		select_playlist(target_id)
	else:
		current_playlist_id = ""
		selected_song_item_id = ""
		_render_selected_playlist_header({})
		_render_playlist_items([])

func _playlist_exists(pl_id: String) -> bool:
	for p in playlists_list:
		if str(p.get("id", "")) == pl_id:
			return true
	return false

func _on_search_library_changed(q: String) -> void:
	var clean_q = q.strip_edges()
	if clean_q.is_empty():
		_render_playlists_list()
	else:
		_render_library_search_results(clean_q)

func _render_playlists_list() -> void:
	if not playlists_vbox: return
	for c in playlists_vbox.get_children():
		playlists_vbox.remove_child(c)
		c.queue_free()

	if playlists_list.size() == 0:
		return

	var top_slot = PlaylistDropSlotControl.new(self, 0)
	playlists_vbox.add_child(top_slot)

	for i in range(playlists_list.size()):
		var pl = playlists_list[i]
		var pl_id = str(pl.get("id", ""))
		var pl_name = str(pl.get("name", "Untitled"))
		var item_cnt = int(pl.get("item_count", 0))

		var card = PlaylistCardControl.new(pl_id, i, pl_name, item_cnt, self, (pl_id == current_playlist_id))
		playlists_vbox.add_child(card)

		var slot = PlaylistDropSlotControl.new(self, i + 1)
		playlists_vbox.add_child(slot)

func _render_library_search_results(query: String) -> void:
	if not playlists_vbox: return
	for c in playlists_vbox.get_children():
		playlists_vbox.remove_child(c)
		c.queue_free()

	var search_results = playlists_svc.search_library(query)

	var header_lbl = Label.new()
	header_lbl.text = "Search Results (" + str(search_results.size()) + ")"
	header_lbl.add_theme_font_size_override("font_size", 12)
	header_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.52, 1.0))
	playlists_vbox.add_child(header_lbl)

	for res in search_results:
		var pl_name = str(res.get("playlist_name", "Playlist"))
		var item_title = str(res.get("title", "Untitled"))
		var item_artist = str(res.get("artist", ""))
		var target_pl_id = str(res.get("playlist_id", ""))

		var btn_res = Button.new()
		btn_res.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn_res.text = "🎵 " + item_title + (" by " + item_artist if item_artist != "" else "") + "\n   in " + pl_name
		btn_res.add_theme_font_size_override("font_size", 12)
		_style_button(btn_res)
		btn_res.pressed.connect(func():
			select_playlist(target_pl_id)
		)
		playlists_vbox.add_child(btn_res)

func select_playlist(playlist_id: String) -> void:
	current_playlist_id = playlist_id
	selected_song_item_id = ""
	var pl = playlists_svc.get_playlist_by_id(playlist_id)

	_render_playlists_list()
	_render_selected_playlist_header(pl)
	load_playlist_items()

func reorder_playlist_to_index(playlist_id: String, target_index: int) -> void:
	if not playlists_svc: return
	playlists_svc.reorder_playlist_to_index(playlist_id, target_index)
	load_playlists(playlist_id)

func _render_selected_playlist_header(pl: Dictionary) -> void:
	if pl.is_empty():
		selected_playlist_title.text = "No Playlist Selected"
		selected_playlist_meta.text = "Create or select a playlist from the library panel to view and manage songs."
		btn_add_media.disabled = true
		if btn_paste_url: btn_paste_url.disabled = true
		btn_search_youtube.disabled = true
		btn_duplicate_playlist.disabled = true
		btn_edit_playlist.disabled = true
		btn_delete_playlist.disabled = true
	else:
		var p_name = str(pl.get("name", "Untitled"))
		var desc = str(pl.get("description", "")).strip_edges()
		var count = int(pl.get("item_count", 0))

		selected_playlist_title.text = p_name
		var meta_text = str(count) + (" item" if count == 1 else " items")
		if desc != "":
			meta_text += " • " + desc
		selected_playlist_meta.text = meta_text

		btn_add_media.disabled = false
		if btn_paste_url: btn_paste_url.disabled = false
		btn_search_youtube.disabled = false
		btn_duplicate_playlist.disabled = false
		btn_edit_playlist.disabled = false
		btn_delete_playlist.disabled = false

# ==============================================================================
# PLAYLIST ITEMS UI (SELECT & DRAG)
# ==============================================================================

func load_playlist_items() -> void:
	if current_playlist_id.is_empty() or not playlists_svc:
		_render_playlist_items([])
		return

	items_list = playlists_svc.get_playlist_items(current_playlist_id)
	var q = item_search_input.text.strip_edges().to_lower()
	if q.is_empty():
		_render_playlist_items(items_list)
	else:
		var filtered = []
		for it in items_list:
			var title_str = str(it.get("title", "")).to_lower()
			var artist_str = str(it.get("artist", "")).to_lower()
			var notes_str = str(it.get("notes", "")).to_lower()
			var url_str = str(it.get("url", "")).to_lower()
			if q in title_str or q in artist_str or q in notes_str or q in url_str:
				filtered.append(it)
		_render_playlist_items(filtered)

func _on_search_items_changed(_q: String) -> void:
	load_playlist_items()

func _render_playlist_items(items: Array) -> void:
	if not items_vbox: return
	for c in items_vbox.get_children():
		items_vbox.remove_child(c)
		c.queue_free()

	if current_playlist_id.is_empty():
		return

	if items.size() == 0:
		var empty_ctrl = EmptyPlaylistControl.new(self, current_playlist_id)
		items_vbox.add_child(empty_ctrl)
		return

	var top_slot = SongDropSlotControl.new(self, 0)
	items_vbox.add_child(top_slot)

	for i in range(items.size()):
		var it = items[i]
		var it_id = str(it.get("id", ""))
		var card = SongCardControl.new(it_id, i, it, self, (it_id == selected_song_item_id))
		items_vbox.add_child(card)

		var slot = SongDropSlotControl.new(self, i + 1)
		items_vbox.add_child(slot)

func set_selected_song_item(item_id: String) -> void:
	selected_song_item_id = item_id
	if not items_vbox: return
	for c in items_vbox.get_children():
		if c is SongCardControl:
			c.set_selected(c.item_id == selected_song_item_id)

func reorder_song_to_index(item_id: String, target_index: int) -> void:
	if not playlists_svc: return
	playlists_svc.reorder_song_to_index(item_id, target_index)
	load_playlist_items()

func _get_source_badge_color(st: String) -> Color:
	match st:
		"youtube": return Color(0.85, 0.15, 0.15, 1.0)
		"spotify": return Color(0.12, 0.72, 0.33, 1.0)
		"apple_music": return Color(0.95, 0.25, 0.40, 1.0)
		"local_file": return Color(0.20, 0.45, 0.75, 1.0)
		"web": return Color(0.40, 0.30, 0.70, 1.0)
		_: return Color(0.45, 0.50, 0.55, 1.0)

func _get_source_icon(st: String) -> String:
	match st:
		"youtube": return "▶️"
		"spotify": return "🟢"
		"apple_music": return "🍎"
		"local_file": return "📁"
		"web": return "🌐"
		_: return "🎵"

func _format_duration(seconds: int) -> String:
	var mins = seconds / 60
	var secs = seconds % 60
	return "%d:%02d" % [mins, secs]

# ==============================================================================
# DRAG AND DROP HELPERS & POSITIONING
# ==============================================================================

func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty():
		return

	var drop_pos = get_global_mouse_position()
	var target_pl_id = current_playlist_id

	if target_pl_id.is_empty() and playlists_list.size() > 0:
		target_pl_id = str(playlists_list[0].get("id", ""))

	var sb_rect = sidebar_panel.get_global_rect() if sidebar_panel else Rect2()

	if sb_rect.has_point(drop_pos):
		if playlists_vbox:
			for child in playlists_vbox.get_children():
				if child is PlaylistCardControl and child.get_global_rect().has_point(drop_pos):
					target_pl_id = child.playlist_id
					break
		for f in files:
			_process_dropped_url_or_file(f, target_pl_id, -1)

	else:
		if not target_pl_id.is_empty():
			for f in files:
				_process_dropped_url_or_file(f, target_pl_id, -1)

func _show_invalid_url_notification(msg: String = "No valid media URL found.") -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "Invalid Media URL"
	dialog.dialog_text = msg + "\n\nPlease paste or drop a valid YouTube, Spotify, Apple Music, or file URL."
	dialog.confirmed.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _show_insert_song_below_dialog(target_index: int) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Insert Song at Position #" + str(target_index + 1)
	dialog.ok_button_text = "Add Song"
	dialog.cancel_button_text = "Cancel"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var lbl = Label.new()
	lbl.text = "Paste or drag a YouTube URL below to insert at position #" + str(target_index + 1) + ":"
	vbox.add_child(lbl)

	var input = LineEdit.new()
	input.placeholder_text = "https://www.youtube.com/watch?v=..."
	input.custom_minimum_size = Vector2(360, 32)
	input.caret_blink = true
	input.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(input)

	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		var url = input.text.strip_edges()
		if not url.is_empty():
			_process_dropped_url_or_file(url, current_playlist_id, target_index)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()

func _process_dropped_url_or_file(raw_input: String, target_playlist_id: String, target_index: int) -> void:
	if target_playlist_id.is_empty() or not playlists_svc:
		return

	var validation = playlists_svc.validate_and_extract_url(raw_input)
	if not validation["is_valid"]:
		_show_invalid_url_notification("No valid media URL found.")
		return

	var canonical_url = str(validation["canonical_url"])
	var src_type = str(validation["source_type"])
	var vid_id = str(validation["video_id"])
	var default_title = str(validation["title"])
	if default_title == "": default_title = "Dropped Media"

	var target_pl = playlists_svc.get_playlist_by_id(target_playlist_id)
	var target_pl_name = str(target_pl.get("name", "Playlist"))

	# Duplicate check using canonical video_id or URL
	if playlists_svc.check_duplicate_in_playlist(target_playlist_id, canonical_url, default_title):
		_show_duplicate_warning_dialog(target_pl_name, func(add_anyway: bool):
			if add_anyway:
				_execute_insert_and_fetch(target_playlist_id, target_index, canonical_url, validation, vid_id, src_type, canonical_url, default_title)
		)
		return

	_execute_insert_and_fetch(target_playlist_id, target_index, canonical_url, validation, vid_id, src_type, canonical_url, default_title)

func _execute_insert_and_fetch(
	target_playlist_id: String,
	target_index: int,
	raw_input: String,
	meta: Dictionary,
	vid_id: String,
	src_type: String,
	canonical_url: String,
	default_title: String
) -> void:
	var final_index = target_index
	var cur_items = playlists_svc.get_playlist_items(target_playlist_id)
	if final_index < 0 or final_index > cur_items.size():
		final_index = cur_items.size()

	if src_type == "youtube" and vid_id != "":
		# Insert temporary row while fetching metadata
		var temp_res = playlists_svc.insert_playlist_item_at_index(
			target_playlist_id,
			final_index,
			"⚡ Getting video information...",
			"",
			"youtube",
			canonical_url,
			0,
			"Dropped YouTube link",
			str(meta.get("thumbnail_url", ""))
		)

		if target_playlist_id == current_playlist_id:
			load_playlist_items()

		if temp_res["success"]:
			var temp_item_id = str(temp_res["item"]["id"])
			playlists_svc.fetch_youtube_oembed(vid_id, self, func(oembed_res: Dictionary):
				if oembed_res["success"]:
					var fetched_title = str(oembed_res.get("title", default_title))
					var fetched_artist = str(oembed_res.get("artist", ""))
					var fetched_thumb = str(oembed_res.get("thumbnail_url", ""))
					playlists_svc.update_playlist_item(temp_item_id, fetched_title, fetched_artist, "youtube", canonical_url, "", 0, fetched_thumb)
					if target_playlist_id == current_playlist_id:
						load_playlist_items()
				else:
					# Metadata retrieval failed (Section H)
					playlists_svc.update_playlist_item(temp_item_id, "YouTube Video (" + vid_id + ")", "", "youtube", canonical_url, "", 0, str(meta.get("thumbnail_url", "")))
					if target_playlist_id == current_playlist_id:
						load_playlist_items()
					var fallback_item = playlists_svc.get_item_by_id(temp_item_id)
					_show_add_edit_item_dialog(fallback_item, "Could not retrieve video information. You can enter it manually.")
			)
	else:
		playlists_svc.insert_playlist_item_at_index(
			target_playlist_id,
			final_index,
			default_title,
			"",
			src_type,
			canonical_url,
			0,
			"Dropped media reference",
			""
		)
		if target_playlist_id == current_playlist_id:
			load_playlist_items()

# ==============================================================================
# DIALOGS & CONFIRMATIONS
# ==============================================================================

func _show_remove_song_confirmation(item_id: String, item_data: Dictionary, playlist_name: String) -> void:
	var song_title = str(item_data.get("title", "this song"))
	var dialog = Window.new()
	dialog.title = "Remove Item Confirmation"
	dialog.size = Vector2i(440, 180)
	dialog.exclusive = true
	dialog.unresizable = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var msg_lbl = Label.new()
	msg_lbl.text = "Remove “" + song_title + "” from\n“" + playlist_name + "”?"
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(msg_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	_style_button(btn_cancel)
	var close_act = func(): dialog.queue_free()
	btn_cancel.pressed.connect(close_act)
	dialog.close_requested.connect(close_act)
	btn_hbox.add_child(btn_cancel)

	var btn_remove = Button.new()
	btn_remove.text = "Remove"
	_style_button(btn_remove, false, true) # Destructive red style
	btn_remove.pressed.connect(func():
		playlists_svc.delete_playlist_item(item_id)
		dialog.queue_free()
		load_playlist_items()
	)
	btn_hbox.add_child(btn_remove)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

func _show_duplicate_warning_dialog(target_playlist_name: String, callback: Callable) -> void:
	var dialog = Window.new()
	dialog.title = "Duplicate Item Warning"
	dialog.size = Vector2i(440, 180)
	dialog.exclusive = true
	dialog.unresizable = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var msg_lbl = Label.new()
	msg_lbl.text = "⚠️ This video is already in " + target_playlist_name + ".\nDo you want to add it anyway?"
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(msg_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	_style_button(btn_cancel)
	var close_act = func():
		dialog.queue_free()
		callback.call(false)
	btn_cancel.pressed.connect(close_act)
	dialog.close_requested.connect(close_act)
	btn_hbox.add_child(btn_cancel)

	var btn_add = Button.new()
	btn_add.text = "Add Anyway"
	_style_button(btn_add, true)
	btn_add.pressed.connect(func():
		dialog.queue_free()
		callback.call(true)
	)
	btn_hbox.add_child(btn_add)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

func _on_create_playlist_pressed() -> void:
	_show_playlist_dialog()

func _on_edit_playlist_pressed() -> void:
	if current_playlist_id.is_empty(): return
	var pl = playlists_svc.get_playlist_by_id(current_playlist_id)
	_show_playlist_dialog(pl)

func _show_playlist_dialog(existing_pl: Dictionary = {}) -> void:
	var dialog = Window.new()
	dialog.title = "Edit Playlist" if not existing_pl.is_empty() else "Create New Playlist"
	dialog.size = Vector2i(450, 300)
	dialog.exclusive = true
	dialog.unresizable = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = "Playlist Name:"
	vbox.add_child(name_lbl)

	var name_edit = LineEdit.new()
	name_edit.text = str(existing_pl.get("name", ""))
	name_edit.placeholder_text = "e.g. Sunday Gathering, College Study..."
	name_edit.caret_blink = true
	name_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(name_edit)

	var desc_lbl = Label.new()
	desc_lbl.text = "Description / Notes (Optional):"
	vbox.add_child(desc_lbl)

	var desc_edit = TextEdit.new()
	desc_edit.text = str(existing_pl.get("description", ""))
	desc_edit.custom_minimum_size = Vector2(0, 80)
	desc_edit.caret_blink = true
	desc_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(desc_edit)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	_style_button(btn_cancel)
	var close_act = func(): dialog.queue_free()
	btn_cancel.pressed.connect(close_act)
	dialog.close_requested.connect(close_act)
	btn_hbox.add_child(btn_cancel)

	var btn_save = Button.new()
	btn_save.text = "Save Playlist"
	_style_button(btn_save, true)
	btn_save.pressed.connect(func():
		var p_name = name_edit.text.strip_edges()
		if p_name.is_empty(): return
		var p_desc = desc_edit.text.strip_edges()
		if existing_pl.is_empty():
			var res = playlists_svc.create_playlist(p_name, p_desc)
			if res["success"]:
				dialog.queue_free()
				load_playlists(str(res["playlist"]["id"]))
		else:
			var pl_id = str(existing_pl["id"])
			playlists_svc.update_playlist(pl_id, p_name, p_desc)
			dialog.queue_free()
			load_playlists(pl_id)
	)
	btn_hbox.add_child(btn_save)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

func _on_duplicate_playlist_pressed() -> void:
	if current_playlist_id.is_empty(): return
	var res = playlists_svc.duplicate_playlist(current_playlist_id)
	if res["success"]:
		load_playlists(str(res["playlist"]["id"]))

func _on_delete_playlist_pressed() -> void:
	if current_playlist_id.is_empty(): return
	var pl = playlists_svc.get_playlist_by_id(current_playlist_id)
	var pl_name = str(pl.get("name", "Playlist"))

	var dialog = Window.new()
	dialog.title = "Delete Playlist Confirmation"
	dialog.size = Vector2i(420, 180)
	dialog.exclusive = true
	dialog.unresizable = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var msg_lbl = Label.new()
	msg_lbl.text = "Are you sure you want to delete '" + pl_name + "'?\nAll songs in this playlist will be removed."
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(msg_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	_style_button(btn_cancel)
	var close_act = func(): dialog.queue_free()
	btn_cancel.pressed.connect(close_act)
	dialog.close_requested.connect(close_act)
	btn_hbox.add_child(btn_cancel)

	var btn_del = Button.new()
	btn_del.text = "Delete Playlist"
	_style_button(btn_del, false, true)
	btn_del.pressed.connect(func():
		playlists_svc.delete_playlist(current_playlist_id)
		dialog.queue_free()
		current_playlist_id = ""
		load_playlists()
	)
	btn_hbox.add_child(btn_del)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

func _on_add_media_pressed() -> void:
	if current_playlist_id.is_empty(): return
	_show_add_edit_item_dialog({})

func _show_add_edit_item_dialog(existing_item: Dictionary = {}, notice_msg: String = "") -> void:
	var dialog = Window.new()
	dialog.title = "Edit Media Item" if not existing_item.is_empty() else "Add Music / Media"
	dialog.size = Vector2i(520, 480)
	dialog.exclusive = true
	dialog.unresizable = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# URL / Path input with auto detect
	var url_lbl = Label.new()
	url_lbl.text = "URL or File Path (YouTube, Spotify, Apple Music, File):"
	vbox.add_child(url_lbl)

	var url_hbox = HBoxContainer.new()
	url_hbox.add_theme_constant_override("separation", 6)

	var url_edit = LineEdit.new()
	url_edit.text = str(existing_item.get("url", ""))
	url_edit.placeholder_text = "Paste https://www.youtube.com/watch?v=... or file path"
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_edit.caret_blink = true
	url_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	url_hbox.add_child(url_edit)

	var btn_detect = Button.new()
	btn_detect.text = "⚡ Refresh Metadata" if not existing_item.is_empty() else "⚡ Fetch Info"
	_style_button(btn_detect)
	url_hbox.add_child(btn_detect)
	vbox.add_child(url_hbox)

	var status_lbl = Label.new()
	status_lbl.text = notice_msg
	status_lbl.add_theme_font_size_override("font_size", 12)
	if notice_msg != "":
		status_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
	vbox.add_child(status_lbl)

	# Fields
	var title_lbl = Label.new()
	title_lbl.text = "Title:"
	vbox.add_child(title_lbl)

	var title_edit = LineEdit.new()
	title_edit.text = str(existing_item.get("title", ""))
	title_edit.placeholder_text = "Song or Media Title"
	title_edit.caret_blink = true
	title_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_edit)

	var artist_lbl = Label.new()
	artist_lbl.text = "Artist / Creator:"
	vbox.add_child(artist_lbl)

	var artist_edit = LineEdit.new()
	artist_edit.text = str(existing_item.get("artist", ""))
	artist_edit.placeholder_text = "Artist, Group, or Channel"
	artist_edit.caret_blink = true
	artist_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(artist_edit)

	var source_lbl = Label.new()
	source_lbl.text = "Source Type:"
	vbox.add_child(source_lbl)

	var source_option = OptionButton.new()
	var sources = ["youtube", "spotify", "apple_music", "web", "local_file", "other"]
	var cur_src = str(existing_item.get("source_type", "youtube"))
	var sel_idx = 0
	for idx in range(sources.size()):
		var s = sources[idx]
		source_option.add_item(s.to_upper().replacen("_", " "), idx)
		if s == cur_src: sel_idx = idx
	source_option.select(sel_idx)
	vbox.add_child(source_option)

	var notes_lbl = Label.new()
	notes_lbl.text = "Notes (Optional):"
	vbox.add_child(notes_lbl)

	var notes_edit = LineEdit.new()
	notes_edit.text = str(existing_item.get("notes", ""))
	notes_edit.placeholder_text = "Optional performance notes or key info"
	notes_edit.caret_blink = true
	notes_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(notes_edit)

	var _last_fetched_vid_id = ""

	var trigger_fetch = func(raw_url: String):
		var meta = playlists_svc.detect_url_metadata(raw_url)
		var det_src = str(meta.get("source_type", "youtube"))
		for idx in range(sources.size()):
			if sources[idx] == det_src:
				source_option.select(idx)
				break

		var vid_id = str(meta.get("video_id", ""))
		if vid_id != "" and vid_id != _last_fetched_vid_id:
			_last_fetched_vid_id = vid_id
			status_lbl.text = "⚡ Getting video information from YouTube..."
			status_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 0.10, 1.0))

			playlists_svc.fetch_youtube_oembed(vid_id, _http_fetcher, func(res: Dictionary):
				if not is_instance_valid(dialog) or not dialog.visible: return
				if res["success"]:
					if existing_item.is_empty() or title_edit.text.strip_edges().is_empty():
						title_edit.text = str(res.get("title", ""))
					if existing_item.is_empty() or artist_edit.text.strip_edges().is_empty():
						artist_edit.text = str(res.get("artist", ""))
					if res.get("canonical_url", "") != "":
						url_edit.text = str(res["canonical_url"])
					status_lbl.text = "✅ Video information retrieved from YouTube!"
					status_lbl.add_theme_color_override("font_color", Color(0.12, 0.65, 0.25, 1.0))
				else:
					status_lbl.text = "Could not retrieve video information. You can enter it manually."
					status_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
					if title_edit.text.strip_edges().is_empty():
						title_edit.text = "YouTube Video (" + vid_id + ")"
			)

	btn_detect.pressed.connect(func():
		_last_fetched_vid_id = ""
		trigger_fetch.call(url_edit.text)
	)

	url_edit.text_changed.connect(func(new_text: String):
		trigger_fetch.call(new_text)
	)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	_style_button(btn_cancel)
	var close_act = func(): dialog.queue_free()
	btn_cancel.pressed.connect(close_act)
	dialog.close_requested.connect(close_act)
	btn_hbox.add_child(btn_cancel)

	var btn_save = Button.new()
	btn_save.text = "Save Item"
	_style_button(btn_save, true)
	btn_save.pressed.connect(func():
		var i_url = url_edit.text.strip_edges()
		var i_title = title_edit.text.strip_edges()
		var i_artist = artist_edit.text.strip_edges()
		var i_src = sources[source_option.selected]
		var i_notes = notes_edit.text.strip_edges()

		if i_title.is_empty():
			if i_url != "":
				var meta = playlists_svc.detect_url_metadata(i_url)
				i_title = str(meta.get("title", "Untitled Media"))
			else:
				i_title = "Untitled Media"

		var meta_thumb = ""
		if i_src == "youtube":
			var meta = playlists_svc.detect_url_metadata(i_url)
			meta_thumb = str(meta.get("thumbnail_url", ""))

		var cur_pl = playlists_svc.get_playlist_by_id(current_playlist_id)
		var cur_pl_name = str(cur_pl.get("name", "Playlist"))

		if existing_item.is_empty() and playlists_svc.check_duplicate_in_playlist(current_playlist_id, i_url, i_title):
			_show_duplicate_warning_dialog(cur_pl_name, func(add_anyway: bool):
				if add_anyway:
					playlists_svc.add_playlist_item(current_playlist_id, i_title, i_artist, i_src, i_url, 0, i_notes, meta_thumb)
					dialog.queue_free()
					load_playlist_items()
			)
			return

		if existing_item.is_empty():
			playlists_svc.add_playlist_item(current_playlist_id, i_title, i_artist, i_src, i_url, 0, i_notes, meta_thumb)
		else:
			var item_id = str(existing_item["id"])
			playlists_svc.update_playlist_item(item_id, i_title, i_artist, i_src, i_url, i_notes, 0, meta_thumb)

		dialog.queue_free()
		load_playlist_items()
	)
	btn_hbox.add_child(btn_save)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

func show_move_copy_dialog(item_id: String, action_mode: String) -> void:
	var dialog = Window.new()
	dialog.title = "Move Item to Playlist" if action_mode == "move" else "Copy Item to Playlist"
	dialog.size = Vector2i(420, 220)
	dialog.exclusive = true
	dialog.unresizable = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var prompt_lbl = Label.new()
	prompt_lbl.text = "Select Destination Playlist:"
	vbox.add_child(prompt_lbl)

	var target_option = OptionButton.new()
	var target_ids = []
	var idx_counter = 0
	for pl in playlists_list:
		var pid = str(pl.get("id", ""))
		if action_mode == "move" and pid == current_playlist_id:
			continue
		target_option.add_item("🎵 " + str(pl.get("name", "Playlist")), idx_counter)
		target_ids.append(pid)
		idx_counter += 1

	vbox.add_child(target_option)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	_style_button(btn_cancel)
	var close_act = func(): dialog.queue_free()
	btn_cancel.pressed.connect(close_act)
	dialog.close_requested.connect(close_act)
	btn_hbox.add_child(btn_cancel)

	var btn_exec = Button.new()
	btn_exec.text = "Move Item" if action_mode == "move" else "Copy Item"
	_style_button(btn_exec, true)
	btn_exec.pressed.connect(func():
		if target_ids.size() > target_option.selected:
			var dest_id = target_ids[target_option.selected]
			if action_mode == "move":
				playlists_svc.move_item_to_playlist(item_id, dest_id)
			else:
				playlists_svc.copy_item_to_playlist(item_id, dest_id)
			dialog.queue_free()
			load_playlists(current_playlist_id)
	)
	btn_hbox.add_child(btn_exec)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

# ==============================================================================
# YOUTUBE SEARCH DIALOG (API Key Optional)
# ==============================================================================

func _on_search_youtube_pressed() -> void:
	if current_playlist_id.is_empty(): return

	var dialog = Window.new()
	dialog.title = "Search YouTube"
	dialog.size = Vector2i(600, 480)
	dialog.exclusive = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var search_hbox = HBoxContainer.new()
	search_hbox.add_theme_constant_override("separation", 8)

	var query_input = LineEdit.new()
	query_input.placeholder_text = "e.g. Yet Not I But Through Christ In Me CityAlight"
	query_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query_input.caret_blink = true
	query_input.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	search_hbox.add_child(query_input)

	var btn_do_search = Button.new()
	btn_do_search.text = "🔍 Search"
	_style_button(btn_do_search, true)
	search_hbox.add_child(btn_do_search)
	vbox.add_child(search_hbox)

	var results_scroll = ScrollContainer.new()
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var results_vbox = VBoxContainer.new()
	results_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_vbox.add_theme_constant_override("separation", 8)
	results_scroll.add_child(results_vbox)
	vbox.add_child(results_scroll)

	var api_key = playlists_svc.get_youtube_api_key()
	if api_key.is_empty():
		_render_youtube_api_key_missing_banner(results_vbox, dialog)
	else:
		var info_lbl = Label.new()
		info_lbl.text = "Enter song title, artist, or keywords above and click Search."
		info_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
		results_vbox.add_child(info_lbl)

	btn_do_search.pressed.connect(func():
		var q = query_input.text.strip_edges()
		if q.is_empty(): return
		var key = playlists_svc.get_youtube_api_key()
		if key.is_empty():
			_render_youtube_api_key_missing_banner(results_vbox, dialog)
			return

		for c in results_vbox.get_children():
			results_vbox.remove_child(c)
			c.queue_free()

		var loading_lbl = Label.new()
		loading_lbl.text = "Searching YouTube for '" + q + "'..."
		results_vbox.add_child(loading_lbl)

		var url = "https://www.googleapis.com/youtube/v3/search?part=snippet&q=" + q.uri_encode() + "&type=video&maxResults=15&key=" + key
		_yt_search_http.request(url)

		var completion_conn: Callable
		completion_conn = func(_res: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
			if _yt_search_http.request_completed.is_connected(completion_conn):
				_yt_search_http.request_completed.disconnect(completion_conn)

			for c in results_vbox.get_children():
				results_vbox.remove_child(c)
				c.queue_free()

			if code != 200:
				var err_lbl = Label.new()
				err_lbl.text = "YouTube Search API Error (HTTP " + str(code) + "). Check your API key and quotas."
				err_lbl.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2, 1.0))
				results_vbox.add_child(err_lbl)
				return

			var json = JSON.parse_string(body.get_string_from_utf8())
			if not json or not typeof(json) == TYPE_DICTIONARY:
				return

			var items = json.get("items", [])
			if items.size() == 0:
				var no_res = Label.new()
				no_res.text = "No results found on YouTube for '" + q + "'."
				results_vbox.add_child(no_res)
				return

			for item in items:
				var id_dict = item.get("id", {})
				var vid_id = str(id_dict.get("videoId", ""))
				if vid_id.is_empty(): continue
				var snippet = item.get("snippet", {})
				var r_title = str(snippet.get("title", ""))
				var r_channel = str(snippet.get("channelTitle", ""))
				var r_url = "https://www.youtube.com/watch?v=" + vid_id
				var r_thumb = "https://img.youtube.com/vi/" + vid_id + "/hqdefault.jpg"

				var r_card = PanelContainer.new()
				var r_st = StyleBoxFlat.new()
				r_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
				r_st.border_width_left = 3
				r_st.border_color = Color(0.85, 0.15, 0.15, 1.0)
				r_card.add_theme_stylebox_override("panel", r_st)

				var r_hbox = HBoxContainer.new()
				r_hbox.add_theme_constant_override("separation", 10)

				var r_vbox = VBoxContainer.new()
				r_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

				var rt_lbl = Label.new()
				rt_lbl.text = r_title
				rt_lbl.add_theme_font_size_override("font_size", 14)
				r_vbox.add_child(rt_lbl)

				var rc_lbl = Label.new()
				rc_lbl.text = "Channel: " + r_channel + " • " + r_url
				rc_lbl.add_theme_font_size_override("font_size", 11)
				rc_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.58, 1.0))
				r_vbox.add_child(rc_lbl)

				r_hbox.add_child(r_vbox)

				var btn_add_res = Button.new()
				btn_add_res.text = "+ Add to Playlist"
				_style_button(btn_add_res, true)
				btn_add_res.pressed.connect(func():
					var cur_pl = playlists_svc.get_playlist_by_id(current_playlist_id)
					var cur_pl_name = str(cur_pl.get("name", "Playlist"))
					if playlists_svc.check_duplicate_in_playlist(current_playlist_id, r_url, r_title):
						_show_duplicate_warning_dialog(cur_pl_name, func(add_anyway: bool):
							if add_anyway:
								playlists_svc.add_playlist_item(current_playlist_id, r_title, r_channel, "youtube", r_url, 0, "", r_thumb)
								load_playlists(current_playlist_id)
						)
					else:
						playlists_svc.add_playlist_item(current_playlist_id, r_title, r_channel, "youtube", r_url, 0, "", r_thumb)
						load_playlists(current_playlist_id)
				)
				r_hbox.add_child(btn_add_res)

				r_card.add_child(r_hbox)
				results_vbox.add_child(r_card)
		
		_yt_search_http.request_completed.connect(completion_conn)
	)

	var close_act = func(): dialog.queue_free()
	dialog.close_requested.connect(close_act)

	add_child(dialog)
	dialog.popup_centered()

func _render_youtube_api_key_missing_banner(parent_vbox: VBoxContainer, dialog: Window) -> void:
	for c in parent_vbox.get_children():
		parent_vbox.remove_child(c)
		c.queue_free()

	var banner = PanelContainer.new()
	var b_st = StyleBoxFlat.new()
	b_st.bg_color = Color(0.99, 0.95, 0.90, 1.0)
	b_st.border_width_left = 4
	b_st.border_color = Color(0.88, 0.55, 0.11, 1.0)
	b_st.content_margin_left = 16
	b_st.content_margin_top = 16
	b_st.content_margin_right = 16
	b_st.content_margin_bottom = 16
	banner.add_theme_stylebox_override("panel", b_st)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var title_lbl = Label.new()
	title_lbl.text = "⚠️ Live YouTube Search Requires API Credential Setup"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.65, 0.35, 0.0, 1.0))
	vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = "Proper YouTube search requires a YouTube Data API v3 Key from Google Cloud Console.\n\nTo enable live YouTube search:\n1. Obtain a YouTube Data API v3 key from Google Cloud Console.\n2. Paste your YOUTUBE_API_KEY below or configure it in Settings."
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.25, 0.20, 0.15, 1.0))
	vbox.add_child(desc_lbl)

	var key_hbox = HBoxContainer.new()
	key_hbox.add_theme_constant_override("separation", 8)

	var key_input = LineEdit.new()
	key_input.placeholder_text = "Paste YOUTUBE_API_KEY here..."
	key_input.secret = true
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_input.caret_blink = true
	key_input.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	key_hbox.add_child(key_input)

	var btn_save_key = Button.new()
	btn_save_key.text = "Save Key"
	_style_button(btn_save_key, true)
	btn_save_key.pressed.connect(func():
		var k_val = key_input.text.strip_edges()
		if k_val != "" and db:
			db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL);")
			db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('YOUTUBE_API_KEY', ?);", [k_val])
			dialog.queue_free()
			_on_search_youtube_pressed()
	)
	key_hbox.add_child(btn_save_key)

	vbox.add_child(key_hbox)
	banner.add_child(vbox)
	parent_vbox.add_child(banner)

# ==============================================================================
# HELPER CONTROL CLASSES FOR DRAG AND DROP
# ==============================================================================

class PlaylistDropSlotControl extends PanelContainer:
	var view_ref: Control
	var slot_index: int
	var is_active: bool = false
	var label: Label

	func _init(p_view: Control, p_idx: int) -> void:
		view_ref = p_view
		slot_index = p_idx
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CAN_DROP
		custom_minimum_size = Vector2(0, 6)

		label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		label.visible = false
		add_child(label)

		_update_style(false)

	func _update_style(p_active: bool) -> void:
		is_active = p_active
		var st = StyleBoxFlat.new()
		st.corner_radius_top_left = 4
		st.corner_radius_top_right = 4
		st.corner_radius_bottom_left = 4
		st.corner_radius_bottom_right = 4

		if is_active:
			custom_minimum_size = Vector2(0, 22)
			st.bg_color = Color(0.88, 0.96, 0.91, 1.0)
			st.border_width_left = 2
			st.border_width_top = 2
			st.border_width_right = 2
			st.border_width_bottom = 2
			st.border_color = Color(0.12, 0.65, 0.35, 1.0)
			label.visible = true
			label.text = "── ＋ INSERT PLAYLIST HERE ──"
			label.add_theme_color_override("font_color", Color(0.08, 0.45, 0.22, 1.0))
		else:
			custom_minimum_size = Vector2(0, 6)
			st.bg_color = Color(0, 0, 0, 0.0)
			label.visible = false

		add_theme_stylebox_override("panel", st)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		var can_drop = false
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "playlist":
			can_drop = true

		if can_drop:
			view_ref.set_active_playlist_drop_slot(slot_index)
			return true
		else:
			view_ref.clear_all_drop_slots()
			return false

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			_update_style(false)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		view_ref.clear_all_drop_slots()
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "playlist":
			var from_index = int(data.get("index", -1))
			var target_idx = slot_index
			if from_index >= 0:
				if from_index < target_idx:
					target_idx -= 1
				view_ref.reorder_playlist_to_index(str(data.get("id", "")), target_idx)

class SongDropSlotControl extends PanelContainer:
	var view_ref: Control
	var slot_index: int
	var is_active: bool = false
	var label: Label

	func _init(p_view: Control, p_idx: int) -> void:
		view_ref = p_view
		slot_index = p_idx
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CAN_DROP
		custom_minimum_size = Vector2(0, 6)

		label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.visible = false
		add_child(label)

		_update_style(false)

	func _update_style(p_active: bool) -> void:
		is_active = p_active
		var st = StyleBoxFlat.new()
		st.corner_radius_top_left = 4
		st.corner_radius_top_right = 4
		st.corner_radius_bottom_left = 4
		st.corner_radius_bottom_right = 4

		if is_active:
			custom_minimum_size = Vector2(0, 26)
			st.bg_color = Color(0.88, 0.96, 0.91, 1.0)
			st.border_width_left = 2
			st.border_width_top = 2
			st.border_width_right = 2
			st.border_width_bottom = 2
			st.border_color = Color(0.12, 0.65, 0.35, 1.0)
			label.visible = true
			if slot_index == 0:
				label.text = "────── ＋ INSERT AT TOP (POSITION #1) ──────"
			else:
				label.text = "────── ＋ INSERT AT POSITION #" + str(slot_index + 1) + " ──────"
			label.add_theme_color_override("font_color", Color(0.08, 0.45, 0.22, 1.0))
		else:
			custom_minimum_size = Vector2(0, 6)
			st.bg_color = Color(0, 0, 0, 0.0)
			label.visible = false

		add_theme_stylebox_override("panel", st)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		var can_drop = false
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "song_item":
			can_drop = true
		else:
			var url_str = view_ref._extract_url_from_data(data)
			if url_str != "":
				can_drop = true

		if can_drop:
			view_ref.set_active_song_drop_slot(slot_index)
			return true
		else:
			view_ref.clear_all_drop_slots()
			return false

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			_update_style(false)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		view_ref.clear_all_drop_slots()
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "song_item":
			var from_index = int(data.get("index", -1))
			var target_idx = slot_index
			if from_index >= 0:
				if from_index < target_idx:
					target_idx -= 1
				view_ref.reorder_song_to_index(str(data.get("id", "")), target_idx)
		else:
			var url_str = view_ref._extract_url_from_data(data)
			if url_str == "":
				url_str = DisplayServer.clipboard_get().strip_edges()
			if url_str != "":
				view_ref._process_dropped_url_or_file(url_str, view_ref.current_playlist_id, slot_index)

class PlaylistCardControl extends PanelContainer:
	var playlist_id: String
	var playlist_index: int
	var playlist_name: String
	var view_ref: Control
	var is_selected: bool = false
	var drop_indicator_position: String = ""

	var _mouse_down_pos: Vector2 = Vector2.ZERO
	var _is_mouse_down: bool = false
	var _is_dragging: bool = false

	func _init(p_id: String, p_idx: int, p_name: String, p_count: int, p_view: Control, p_selected: bool) -> void:
		playlist_id = p_id
		playlist_index = p_idx
		playlist_name = p_name
		view_ref = p_view
		is_selected = p_selected

		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CAN_DROP

		_update_style()

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var drag_badge = Label.new()
		drag_badge.text = "≡"
		drag_badge.add_theme_font_size_override("font_size", 16)
		drag_badge.add_theme_color_override("font_color", Color(0.65, 0.70, 0.76, 1.0))
		hbox.add_child(drag_badge)

		var name_vbox = VBoxContainer.new()
		name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl = Label.new()
		name_lbl.text = "🎵 " + p_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
		name_vbox.add_child(name_lbl)

		var meta_lbl = Label.new()
		meta_lbl.text = str(p_count) + (" item" if p_count == 1 else " items")
		meta_lbl.add_theme_font_size_override("font_size", 11)
		meta_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62, 1.0))
		name_vbox.add_child(meta_lbl)

		hbox.add_child(name_vbox)

		var btn_opt = Button.new()
		btn_opt.text = "⋮"
		btn_opt.tooltip_text = "Playlist options"
		btn_opt.custom_minimum_size = Vector2(24, 24)
		view_ref._style_button(btn_opt)
		btn_opt.pressed.connect(func():
			_show_context_menu(btn_opt)
		)
		hbox.add_child(btn_opt)

		add_child(hbox)
		_set_mouse_filter_recursive(self)

	func _update_style() -> void:
		var card_st = StyleBoxFlat.new()
		card_st.corner_radius_top_left = 6
		card_st.corner_radius_top_right = 6
		card_st.corner_radius_bottom_left = 6
		card_st.corner_radius_bottom_right = 6
		card_st.content_margin_left = 12
		card_st.content_margin_right = 12
		card_st.content_margin_top = 10
		card_st.content_margin_bottom = 10

		if drop_indicator_position == "target_add":
			card_st.bg_color = Color(0.92, 0.96, 1.0, 1.0)
			card_st.border_width_left = 4
			card_st.border_width_top = 2
			card_st.border_width_right = 2
			card_st.border_width_bottom = 2
			card_st.border_color = Color(0.12, 0.65, 0.35, 1.0)
		elif is_selected:
			card_st.bg_color = Color(0.92, 0.94, 0.98, 1.0)
			card_st.border_width_left = 4
			card_st.border_color = Color(0.596, 0.192, 0.255, 1.0)
		else:
			card_st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
			card_st.border_width_left = 1
			card_st.border_color = Color(0.88, 0.90, 0.94, 1.0)

		add_theme_stylebox_override("panel", card_st)

	static func _set_mouse_filter_recursive(node: Node) -> void:
		for child in node.get_children():
			if child is Control:
				if not (child is Button or child is OptionButton or child is LineEdit or child is TextEdit or child is MenuButton):
					(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
					_set_mouse_filter_recursive(child)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_is_mouse_down = true
					_mouse_down_pos = event.position
					_is_dragging = false
				else:
					if _is_mouse_down:
						_is_mouse_down = false
						if not _is_dragging:
							var dist = event.position.distance_to(_mouse_down_pos)
							if dist < 6.0:
								view_ref.select_playlist(playlist_id)
						_is_dragging = false
			elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_show_context_menu(self)
		elif event is InputEventMouseMotion:
			if _is_mouse_down and not _is_dragging:
				if event.position.distance_to(_mouse_down_pos) > 6.0:
					_is_dragging = true
					var drag_data = {
						"type": "playlist",
						"id": playlist_id,
						"index": playlist_index
					}
					var preview = _create_drag_preview()
					modulate.a = 0.4
					force_drag(drag_data, preview)

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "playlist":
			var target_slot_idx = playlist_index if at_position.y < (size.y / 2.0) else playlist_index + 1
			view_ref.set_active_playlist_drop_slot(target_slot_idx)
			return true
		elif typeof(data) == TYPE_DICTIONARY and data.get("type") == "song_item":
			view_ref.clear_all_drop_slots()
			return false
		else:
			var url_str = view_ref._extract_url_from_data(data)
			if url_str != "":
				if drop_indicator_position != "target_add":
					drop_indicator_position = "target_add"
					_update_style()
				return true
			view_ref.clear_all_drop_slots()
			return false

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		view_ref.clear_all_drop_slots()
		drop_indicator_position = ""
		_update_style()

		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "playlist":
			var target_slot_idx = playlist_index if at_position.y < (size.y / 2.0) else playlist_index + 1
			var from_index = int(data.get("index", -1))
			var target_idx = target_slot_idx
			if from_index >= 0:
				if from_index < target_idx:
					target_idx -= 1
				view_ref.reorder_playlist_to_index(playlist_id, target_idx)
		else:
			var url_str = view_ref._extract_url_from_data(data)
			if url_str == "":
				url_str = DisplayServer.clipboard_get().strip_edges()
			if url_str != "":
				view_ref._process_dropped_url_or_file(url_str, playlist_id, -1)


	func _create_drag_preview() -> Control:
		var preview = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.596, 0.192, 0.255, 0.95)
		st.corner_radius_top_left = 6
		st.corner_radius_top_right = 6
		st.corner_radius_bottom_left = 6
		st.corner_radius_bottom_right = 6
		st.content_margin_left = 14
		st.content_margin_right = 14
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		st.shadow_color = Color(0, 0, 0, 0.3)
		st.shadow_size = 8
		st.shadow_offset = Vector2(0, 4)
		preview.add_theme_stylebox_override("panel", st)

		var lbl = Label.new()
		lbl.text = "🎵 " + playlist_name
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.add_theme_font_size_override("font_size", 14)
		preview.add_child(lbl)
		return preview

	func _show_context_menu(target_control: Control) -> void:
		var popup = PopupMenu.new()
		popup.add_item("Move Up", 1)
		popup.add_item("Move Down", 2)
		popup.add_item("Move to Top", 3)
		popup.add_item("Move to Bottom", 4)

		popup.id_pressed.connect(func(id: int):
			if id == 1: view_ref.playlists_svc.move_playlist_order(playlist_id, "up")
			elif id == 2: view_ref.playlists_svc.move_playlist_order(playlist_id, "down")
			elif id == 3: view_ref.reorder_playlist_to_index(playlist_id, 0)
			elif id == 4: view_ref.reorder_playlist_to_index(playlist_id, 9999)
			view_ref.load_playlists(playlist_id)
			popup.queue_free()
		)
		popup.popup_hide.connect(func(): popup.queue_free())
		target_control.add_child(popup)
		popup.popup(Rect2i(Vector2i(target_control.global_position), Vector2i(150, 100)))

class SongCardControl extends PanelContainer:
	var item_id: String
	var item_index: int
	var item_data: Dictionary
	var view_ref: Control
	var is_selected: bool = false
	var drop_indicator_position: String = ""

	var _mouse_down_pos: Vector2 = Vector2.ZERO
	var _is_mouse_down: bool = false
	var _is_dragging: bool = false

	var _thumb_rect: TextureRect
	var _fallback_lbl: Label
	var _thumb_url: String = ""

	func _ready() -> void:
		_load_thumbnail_image()

	func _load_thumbnail_image() -> void:
		if _thumb_url.is_empty() or not is_inside_tree():
			return
		var http_thumb = HTTPRequest.new()
		http_thumb.timeout = 6.0
		add_child(http_thumb)
		var headers = PackedStringArray([
			"User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
			"Accept: image/webp,image/apng,image/*,*/*;q=0.8"
		])
		http_thumb.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
			if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 304) and body.size() > 0:
				var img = Image.new()
				var err = img.load_jpg_from_buffer(body)
				if err != OK:
					err = img.load_png_from_buffer(body)
				if err != OK:
					err = img.load_webp_from_buffer(body)
				if err == OK and _thumb_rect and is_instance_valid(_thumb_rect):
					var tex = ImageTexture.create_from_image(img)
					_thumb_rect.texture = tex
					if _fallback_lbl and is_instance_valid(_fallback_lbl):
						_fallback_lbl.visible = false
			http_thumb.queue_free()
		)
		http_thumb.request(_thumb_url, headers)

	func _init(p_id: String, p_idx: int, p_data: Dictionary, p_view: Control, p_selected: bool = false) -> void:
		item_id = p_id
		item_index = p_idx
		item_data = p_data
		view_ref = p_view
		is_selected = p_selected

		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CAN_DROP

		_update_style()

		var title = str(item_data.get("title", "Untitled"))
		var artist = str(item_data.get("artist", ""))
		var source_type = str(item_data.get("source_type", "youtube"))
		var url = str(item_data.get("url", ""))
		var notes = str(item_data.get("notes", ""))
		var dur_sec = int(item_data.get("duration_seconds", 0))

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)

		# Index & Drag handle
		var drag_handle = Label.new()
		drag_handle.text = "≡ " + str(item_index + 1)
		drag_handle.custom_minimum_size = Vector2(32, 0)
		drag_handle.add_theme_font_size_override("font_size", 13)
		drag_handle.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68, 1.0))
		hbox.add_child(drag_handle)

		# Video Thumbnail Picture Frame
		var thumb_frame = PanelContainer.new()
		thumb_frame.custom_minimum_size = Vector2(80, 45)
		thumb_frame.clip_contents = true
		var tf_st = StyleBoxFlat.new()
		tf_st.bg_color = view_ref._get_source_badge_color(source_type)
		tf_st.corner_radius_top_left = 6
		tf_st.corner_radius_top_right = 6
		tf_st.corner_radius_bottom_left = 6
		tf_st.corner_radius_bottom_right = 6
		thumb_frame.add_theme_stylebox_override("panel", tf_st)

		_thumb_rect = TextureRect.new()
		_thumb_rect.custom_minimum_size = Vector2(80, 45)
		_thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb_frame.add_child(_thumb_rect)

		_fallback_lbl = Label.new()
		_fallback_lbl.text = view_ref._get_source_icon(source_type) + "\n" + source_type.to_upper().replacen("_", " ")
		_fallback_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fallback_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_fallback_lbl.add_theme_font_size_override("font_size", 9)
		_fallback_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		thumb_frame.add_child(_fallback_lbl)
		hbox.add_child(thumb_frame)

		_thumb_url = str(item_data.get("thumbnail_url", ""))
		if _thumb_url == "" and source_type == "youtube":
			var vid_id = view_ref.playlists_svc.extract_youtube_video_id(url)
			if vid_id != "":
				_thumb_url = "https://i.ytimg.com/vi/" + vid_id + "/hqdefault.jpg"

		# Main Info VBox with text autowrapping so long titles/URLs fit on screen!
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.custom_minimum_size = Vector2(1, 0)

		var t_lbl = Label.new()
		t_lbl.text = title
		t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t_lbl.custom_minimum_size = Vector2(1, 0)
		t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_lbl.add_theme_font_size_override("font_size", 14)
		t_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
		info_vbox.add_child(t_lbl)

		var sub_parts = []
		if artist != "": sub_parts.append(artist)
		if dur_sec > 0: sub_parts.append(view_ref._format_duration(dur_sec))
		if notes != "": sub_parts.append("📝 Has Notes")

		if sub_parts.size() > 0:
			var sub_lbl = Label.new()
			sub_lbl.text = " • ".join(sub_parts)
			sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sub_lbl.custom_minimum_size = Vector2(1, 0)
			sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sub_lbl.add_theme_font_size_override("font_size", 11)
			sub_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
			info_vbox.add_child(sub_lbl)

		hbox.add_child(info_vbox)

		# Clean Action buttons
		var actions_hbox = HBoxContainer.new()
		actions_hbox.add_theme_constant_override("separation", 6)

		if url != "":
			var btn_play = Button.new()
			btn_play.text = "▶ Play"
			btn_play.tooltip_text = "Play song in StudyCenterHub"
			btn_play.pressed.connect(func():
				print("REAL_PLAY_BUTTON_CLICKED")
				btn_play.text = "CLICK RECEIVED"
				var title_str = str(item_data.get("title", "Song"))
				if view_ref and view_ref.has_method("show_click_received_banner"):
					view_ref.show_click_received_banner(title_str)

				var url_str = str(item_data.get("url", ""))
				print("[REAL_PLAY_CLICK] playlist_id=", view_ref.current_playlist_id, " item_id=", item_id, " title=", title_str, " url=", url_str)
				
				var vid_id = ""
				if view_ref.playlists_svc:
					vid_id = view_ref.playlists_svc.extract_youtube_video_id(url_str)
				print("[REAL_PLAY_VIDEO_ID] video_id=", vid_id)
				
				var svc = view_ref._get_playback_service()
				if svc:
					print("[REAL_PLAY_SERVICE_CALL] service_instance_id=", svc.get_instance_id(), " playlist_id=", view_ref.current_playlist_id, " item_index=", item_index, " video_id=", vid_id)
					var pl_name = view_ref.selected_playlist_title.text if view_ref.selected_playlist_title else "Playlist"
					svc.start_playlist(pl_name, view_ref.items_list, item_index, view_ref.current_playlist_id)
				else:
					print("[PLAYBACK_FAILURE] view_ref._get_playback_service() returned NULL!")
			)
			print("PLAY_BUTTON_SIGNAL_CONNECTED=", btn_play.pressed.get_connections().size() > 0)
			view_ref._style_button(btn_play, true)
			actions_hbox.add_child(btn_play)

		var btn_opt = Button.new()
		btn_opt.text = "⋮"
		btn_opt.tooltip_text = "Song options"
		btn_opt.custom_minimum_size = Vector2(28, 28)
		view_ref._style_button(btn_opt)
		btn_opt.pressed.connect(func():
			_show_options_menu(btn_opt)
		)
		actions_hbox.add_child(btn_opt)

		hbox.add_child(actions_hbox)
		add_child(hbox)
		_set_mouse_filter_recursive(self)

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		var is_valid_drag = false
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "song_item":
			is_valid_drag = true
		else:
			var url_str = view_ref._extract_url_from_data(data)
			if url_str != "":
				is_valid_drag = true

		if is_valid_drag:
			var target_slot_idx = item_index if at_position.y < (size.y / 2.0) else item_index + 1
			view_ref.set_active_song_drop_slot(target_slot_idx)
			return true
		else:
			view_ref.clear_all_drop_slots()
			return false

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		var target_slot_idx = item_index if at_position.y < (size.y / 2.0) else item_index + 1
		view_ref.clear_all_drop_slots()

		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "song_item":
			var from_index = int(data.get("index", -1))
			var target_idx = target_slot_idx
			if from_index >= 0:
				if from_index < target_idx:
					target_idx -= 1
				view_ref.reorder_song_to_index(str(data.get("id", "")), target_idx)
		else:
			var url_str = view_ref._extract_url_from_data(data)
			if url_str == "":
				url_str = DisplayServer.clipboard_get().strip_edges()
			if url_str != "":
				view_ref._process_dropped_url_or_file(url_str, view_ref.current_playlist_id, target_slot_idx)


	func set_selected(p_selected: bool) -> void:
		if is_selected != p_selected:
			is_selected = p_selected
			_update_style()

	func _update_style() -> void:
		var source_type = str(item_data.get("source_type", "youtube"))
		var card_st = StyleBoxFlat.new()
		card_st.bg_color = Color(0.97, 0.98, 1.0, 1.0)
		card_st.border_width_left = 4
		card_st.border_color = view_ref._get_source_badge_color(source_type)
		card_st.corner_radius_top_left = 6
		card_st.corner_radius_top_right = 6
		card_st.corner_radius_bottom_left = 6
		card_st.corner_radius_bottom_right = 6
		card_st.content_margin_left = 12
		card_st.content_margin_right = 12
		card_st.content_margin_top = 8
		card_st.content_margin_bottom = 8

		if is_selected:
			card_st.bg_color = Color(0.92, 0.95, 1.0, 1.0)
			card_st.border_width_top = 1
			card_st.border_width_right = 1
			card_st.border_width_bottom = 1
			card_st.border_color = Color(0.596, 0.192, 0.255, 1.0)

		add_theme_stylebox_override("panel", card_st)

	static func _set_mouse_filter_recursive(node: Node) -> void:
		for child in node.get_children():
			if child is Control:
				if not (child is Button or child is OptionButton or child is LineEdit or child is TextEdit or child is MenuButton):
					(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
					_set_mouse_filter_recursive(child)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_is_mouse_down = true
					_mouse_down_pos = event.position
					_is_dragging = false
					grab_focus()
					view_ref.set_selected_song_item(item_id)
				else:
					if _is_mouse_down:
						_is_mouse_down = false
						_is_dragging = false
			elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_show_options_menu(self)
		elif event is InputEventMouseMotion:
			if _is_mouse_down and not _is_dragging:
				if event.position.distance_to(_mouse_down_pos) > 6.0:
					_is_dragging = true
					var drag_data = {
						"type": "song_item",
						"id": item_id,
						"index": item_index
					}
					var preview = _create_drag_preview()
					modulate.a = 0.4
					force_drag(drag_data, preview)
		elif event is InputEventKey and event.pressed:
			if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				var focus_owner = get_viewport().gui_get_focus_owner()
				if focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is CodeEdit:
					return
				var pl = view_ref.playlists_svc.get_playlist_by_id(view_ref.current_playlist_id)
				var pl_name = str(pl.get("name", "Playlist"))
				view_ref._show_remove_song_confirmation(item_id, item_data, pl_name)
				get_viewport().set_input_as_handled()

	func _create_drag_preview() -> Control:
		var preview = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.20, 0.25, 0.35, 0.95)
		st.corner_radius_top_left = 6
		st.corner_radius_top_right = 6
		st.corner_radius_bottom_left = 6
		st.corner_radius_bottom_right = 6
		st.content_margin_left = 14
		st.content_margin_right = 14
		st.content_margin_top = 10
		st.content_margin_bottom = 10
		st.shadow_color = Color(0, 0, 0, 0.35)
		st.shadow_size = 10
		st.shadow_offset = Vector2(0, 5)
		preview.add_theme_stylebox_override("panel", st)

		var title_str = str(item_data.get("title", "Song"))
		var artist_str = str(item_data.get("artist", ""))
		var lbl = Label.new()
		lbl.text = "🎵 " + title_str + (" — " + artist_str if artist_str != "" else "")
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.add_theme_font_size_override("font_size", 14)
		preview.add_child(lbl)
		return preview

	func _show_options_menu(target_control: Control) -> void:
		var popup = PopupMenu.new()
		popup.add_item("▶ Play Now", 6)
		popup.add_item("▶ Play from Here", 7)
		popup.add_separator()
		popup.add_item("Edit Details", 1)
		popup.add_item("＋ Insert Song Below…", 5)
		popup.add_item("Move to Playlist…", 2)
		popup.add_item("Copy to Playlist…", 3)
		popup.add_separator()
		popup.add_item("Remove from Playlist", 4)

		var pl = view_ref.playlists_svc.get_playlist_by_id(view_ref.current_playlist_id)
		var pl_name = str(pl.get("name", "Playlist"))

		popup.id_pressed.connect(func(id: int):
			if id == 6 or id == 7:
				var svc = view_ref._get_playback_service()
				if svc:
					svc.start_playlist(pl_name, view_ref.items_list, item_index, view_ref.current_playlist_id)
			elif id == 1:
				view_ref._show_add_edit_item_dialog(item_data)
			elif id == 5:
				view_ref._show_insert_song_below_dialog(item_index + 1)
			elif id == 2:
				view_ref.show_move_copy_dialog(item_id, "move")
			elif id == 3:
				view_ref.show_move_copy_dialog(item_id, "copy")
			elif id == 4:
				view_ref._show_remove_song_confirmation(item_id, item_data, pl_name)
			popup.queue_free()
		)
		popup.popup_hide.connect(func(): popup.queue_free())
		target_control.add_child(popup)
		popup.popup(Rect2i(Vector2i(target_control.global_position), Vector2i(180, 180)))


class EmptyPlaylistControl extends PanelContainer:
	var view_ref: Control
	var playlist_id: String
	var is_drag_over: bool = false

	func _init(p_view: Control, p_id: String) -> void:
		view_ref = p_view
		playlist_id = p_id
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CAN_DROP
		custom_minimum_size = Vector2(0, 200)

		_update_style()

		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 10)

		var icon_lbl = Label.new()
		icon_lbl.text = "🎵 🔗"
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 24)
		vbox.add_child(icon_lbl)

		var msg_lbl = Label.new()
		msg_lbl.text = "Copy and paste a YouTube / media link below to add your first song:"
		msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg_lbl.add_theme_font_size_override("font_size", 14)
		msg_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
		vbox.add_child(msg_lbl)

		var drop_input = LineEdit.new()
		drop_input.placeholder_text = "🔗 Paste YouTube URL here to add song..."
		drop_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		drop_input.custom_minimum_size = Vector2(380, 36)
		drop_input.caret_blink = true
		drop_input.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
		drop_input.text_changed.connect(func(new_text: String):
			view_ref._on_quick_url_text_changed(new_text, drop_input, playlist_id, -1)
		)
		drop_input.text_submitted.connect(func(new_text: String):
			view_ref._on_quick_url_text_submitted(new_text, drop_input, playlist_id, -1)
		)
		vbox.add_child(drop_input)

		var btn_hbox = HBoxContainer.new()
		btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_hbox.add_theme_constant_override("separation", 10)

		var btn_paste = Button.new()
		btn_paste.text = "📋 Paste URL"
		view_ref._style_button(btn_paste)
		btn_paste.pressed.connect(func():
			view_ref._on_paste_url_pressed()
		)
		btn_hbox.add_child(btn_paste)

		var btn_add = Button.new()
		btn_add.text = "+ Add Media"
		view_ref._style_button(btn_add, true)
		btn_add.pressed.connect(func():
			view_ref._on_add_media_pressed()
		)
		btn_hbox.add_child(btn_add)

		vbox.add_child(btn_hbox)
		add_child(vbox)

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		if view_ref and view_ref.has_method("_can_drop_data"):
			return view_ref._can_drop_data((global_position + at_position) - view_ref.global_position, data)
		return false

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if view_ref and view_ref.has_method("_drop_data"):
			view_ref._drop_data((global_position + at_position) - view_ref.global_position, data)

	func _update_style() -> void:
		var st = StyleBoxFlat.new()
		if is_drag_over:
			st.bg_color = Color(0.92, 0.96, 1.0, 1.0)
			st.border_width_left = 3
			st.border_width_top = 3
			st.border_width_right = 3
			st.border_width_bottom = 3
			st.border_color = Color(0.12, 0.65, 0.35, 1.0)
		else:
			st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
			st.border_width_left = 2
			st.border_width_top = 2
			st.border_width_right = 2
			st.border_width_bottom = 2
			st.border_color = Color(0.85, 0.88, 0.92, 1.0)
		st.corner_radius_top_left = 8
		st.corner_radius_top_right = 8
		st.corner_radius_bottom_left = 8
		st.corner_radius_bottom_right = 8
		add_theme_stylebox_override("panel", st)
