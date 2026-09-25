extends Control

## Playlists Subsystem Workspace View
## Features robust select-and-drag reordering with force_drag(),
## full-workspace URL drag-and-drop from Safari/Chrome with visual insertion indicators,
## 1-click "+ ADD SONG" unified workflow & Cmd+V shortcut, uncluttered song row UI with options menu (⋮),
## confirmation-backed item removal, keyboard Delete/Backspace removal, duplicate video ID detection,
## automatic non-blocking YouTube synchronization, and keyless oEmbed YouTube metadata fetching.

const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")
const YouTubePlaylistSyncServiceScript = preload("res://src/domain/playlists/youtube_playlist_sync_service.gd")

var db: RefCounted
var playlists_svc: RefCounted
var oauth_svc: Node
var sync_svc: Node

var current_playlist_id: String = ""
var selected_song_item_id: String = ""
var playlists_list: Array = []
var items_list: Array = []

@onready var workspace_split: Control = $MainMargin/WorkspaceHBox
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

var btn_toggle_sidebar: Button
var btn_add_song: Button
var btn_play_playlist: Button
var btn_open_playlist: Button
var btn_header_overflow: Button

var provider_badge_lbl: Label
var sync_badge_lbl: Button

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
	_setup_sidebar_toggle()
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

func _setup_sidebar_toggle() -> void:
	var sidebar_header = $MainMargin/WorkspaceHBox/LibrarySidebarPanel/SidebarMargin/SidebarVBox/SidebarHeaderHBox
	if sidebar_header:
		btn_toggle_sidebar = Button.new()
		btn_toggle_sidebar.text = "◀"
		btn_toggle_sidebar.tooltip_text = "Collapse / Expand Playlist Library Sidebar"
		btn_toggle_sidebar.custom_minimum_size = Vector2(28, 28)
		_style_button(btn_toggle_sidebar)
		btn_toggle_sidebar.pressed.connect(func():
			if sidebar_panel:
				sidebar_panel.visible = not sidebar_panel.visible
				btn_toggle_sidebar.text = "▶" if not sidebar_panel.visible else "◀"
		)
		sidebar_header.add_child(btn_toggle_sidebar)
		sidebar_header.move_child(btn_toggle_sidebar, 0)

func _setup_header_actions() -> void:
	# Hide obsolete competing buttons in tscn HBox
	if btn_add_media: btn_add_media.visible = false
	if btn_search_youtube: btn_search_youtube.visible = false
	if btn_edit_playlist: btn_edit_playlist.visible = false
	if btn_duplicate_playlist: btn_duplicate_playlist.visible = false
	if btn_delete_playlist: btn_delete_playlist.visible = false

	# Setup Badges and Title layout inside TitleVBox
	var title_vbox = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderTopHBox/TitleVBox
	if title_vbox:
		var badges_hbox = HBoxContainer.new()
		badges_hbox.add_theme_constant_override("separation", 8)

		provider_badge_lbl = Label.new()
		provider_badge_lbl.text = "YOUTUBE"
		provider_badge_lbl.add_theme_font_size_override("font_size", 10)
		provider_badge_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		var badge_st = StyleBoxFlat.new()
		badge_st.bg_color = Color(0.85, 0.15, 0.15, 1.0)
		badge_st.content_margin_left = 6
		badge_st.content_margin_right = 6
		badge_st.content_margin_top = 2
		badge_st.content_margin_bottom = 2
		badge_st.corner_radius_top_left = 4
		badge_st.corner_radius_top_right = 4
		badge_st.corner_radius_bottom_left = 4
		badge_st.corner_radius_bottom_right = 4
		provider_badge_lbl.add_theme_stylebox_override("panel", badge_st)
		badges_hbox.add_child(provider_badge_lbl)

		sync_badge_lbl = Button.new()
		sync_badge_lbl.text = "✓ Synced"
		sync_badge_lbl.tooltip_text = "Click to view sync options or retry synchronization"
		sync_badge_lbl.add_theme_font_size_override("font_size", 11)
		_style_button(sync_badge_lbl)
		sync_badge_lbl.pressed.connect(_on_sync_badge_clicked)
		badges_hbox.add_child(sync_badge_lbl)

		title_vbox.add_child(badges_hbox)
		title_vbox.move_child(badges_hbox, 0)

	# Setup compact top-right overflow menu button
	var mgmt_hbox = $MainMargin/WorkspaceHBox/DetailWorkspacePanel/DetailMargin/DetailVBox/HeaderVBox/HeaderTopHBox/PlaylistMgmtHBox
	if mgmt_hbox:
		btn_header_overflow = Button.new()
		btn_header_overflow.text = "⋮"
		btn_header_overflow.tooltip_text = "Playlist management options"
		btn_header_overflow.custom_minimum_size = Vector2(34, 34)
		_style_button(btn_header_overflow)
		btn_header_overflow.pressed.connect(func():
			_show_header_overflow_menu(btn_header_overflow)
		)
		mgmt_hbox.add_child(btn_header_overflow)

	# Setup primary Action Toolbar
	if header_actions_hbox:
		for c in header_actions_hbox.get_children():
			if c != btn_add_media and c != btn_search_youtube:
				c.visible = false

		btn_play_playlist = Button.new()
		btn_play_playlist.text = "▶ PLAY"
		btn_play_playlist.tooltip_text = "Open and play this real playlist on YouTube in your web browser"
		btn_play_playlist.custom_minimum_size = Vector2(110, 36)
		_style_button(btn_play_playlist, true)
		btn_play_playlist.pressed.connect(_on_play_playlist_pressed)
		header_actions_hbox.add_child(btn_play_playlist)

		btn_open_playlist = Button.new()
		btn_open_playlist.text = "↗ OPEN IN YOUTUBE"
		btn_open_playlist.tooltip_text = "Open external YouTube playlist page"
		btn_open_playlist.custom_minimum_size = Vector2(150, 36)
		_style_button(btn_open_playlist)
		btn_open_playlist.pressed.connect(_on_open_playlist_pressed)
		header_actions_hbox.add_child(btn_open_playlist)

		btn_add_song = Button.new()
		btn_add_song.text = "+ ADD SONG"
		btn_add_song.tooltip_text = "Add YouTube video, web link, or local media song"
		btn_add_song.custom_minimum_size = Vector2(120, 36)
		_style_button(btn_add_song, true)
		btn_add_song.pressed.connect(_show_add_song_dialog)
		header_actions_hbox.add_child(btn_add_song)

func _on_play_playlist_pressed() -> void:
	if sync_svc and not current_playlist_id.is_empty():
		var opened = sync_svc.open_playlist_in_browser(current_playlist_id)
		if not opened:
			var res = await sync_svc.sync_playlist(current_playlist_id)
			if res.get("success", false):
				sync_svc.open_playlist_in_browser(current_playlist_id)
			else:
				_show_temporary_toast("Could not open playlist on YouTube: " + str(res.get("error", "")), true)

func _on_open_playlist_pressed() -> void:
	if sync_svc and not current_playlist_id.is_empty():
		sync_svc.open_playlist_in_browser(current_playlist_id)

func _on_copy_playlist_link_pressed() -> void:
	if playlists_svc and not current_playlist_id.is_empty():
		var link = playlists_svc.get_playlist_provider_link(current_playlist_id, "youtube")
		var ext_url = str(link.get("external_playlist_url", ""))
		if not ext_url.is_empty():
			DisplayServer.clipboard_set(ext_url)
			_show_temporary_toast("✓ Copied YouTube playlist link to clipboard")
		else:
			_show_temporary_toast("No YouTube playlist link generated yet.", true)

func _on_sync_playlist_pressed() -> void:
	if current_playlist_id.is_empty(): return
	_trigger_auto_sync(current_playlist_id)

func _on_sync_badge_clicked() -> void:
	if current_playlist_id.is_empty(): return
	_trigger_auto_sync(current_playlist_id)

func _show_header_overflow_menu(target_control: Control) -> void:
	if current_playlist_id.is_empty(): return
	var popup = PopupMenu.new()
	popup.add_item("✏️ Edit Playlist Name/Desc", 1)
	popup.add_item("📋 Duplicate Playlist", 2)

	var link = playlists_svc.get_playlist_provider_link(current_playlist_id, "youtube") if playlists_svc else {}
	var ext_id = str(link.get("external_playlist_id", ""))
	if not ext_id.is_empty():
		popup.add_item("📋 Copy YouTube Playlist Link", 3)
		popup.add_item("🔄 Sync Now with YouTube", 4)

	popup.add_separator()
	popup.add_item("🗑️ Delete Playlist", 5)

	popup.id_pressed.connect(func(id: int):
		match id:
			1: _on_edit_playlist_pressed()
			2: _on_duplicate_playlist_pressed()
			3: _on_copy_playlist_link_pressed()
			4: _on_sync_playlist_pressed()
			5: _on_delete_playlist_pressed()
		popup.queue_free()
	)
	popup.popup_hide.connect(func(): popup.queue_free())
	target_control.add_child(popup)
	popup.popup(Rect2i(Vector2i(target_control.global_position), Vector2i(220, 160)))

func _trigger_auto_sync(playlist_id: String) -> void:
	if not playlists_svc or playlist_id.is_empty(): return
	var link = playlists_svc.get_playlist_provider_link(playlist_id, "youtube")
	var ext_id = str(link.get("external_playlist_id", ""))
	if ext_id.is_empty(): return # Not linked to YouTube yet

	playlists_svc.update_playlist_sync_status(playlist_id, "youtube", "syncing")
	var pl = playlists_svc.get_playlist_by_id(playlist_id)
	_render_selected_playlist_header(pl)
	_render_playlists_list()

	if sync_svc:
		var res = await sync_svc.sync_playlist(playlist_id)
		if not res.get("success", false):
			var err_msg = str(res.get("error", "Sync failed."))
			playlists_svc.update_playlist_sync_status(playlist_id, "youtube", "sync_error", err_msg)
			_show_temporary_toast("⚠ YouTube Sync: " + err_msg, true)
		else:
			_show_temporary_toast("✓ Synced with YouTube")
		var updated_pl = playlists_svc.get_playlist_by_id(playlist_id)
		_render_selected_playlist_header(updated_pl)
		_render_playlists_list()

func _show_temporary_toast(text: String, is_error: bool = false) -> void:
	var toast = PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 100
	var st = StyleBoxFlat.new()
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.content_margin_left = 16
	st.content_margin_top = 10
	st.content_margin_right = 16
	st.content_margin_bottom = 10
	st.shadow_color = Color(0, 0, 0, 0.25)
	st.shadow_size = 6

	if is_error:
		st.bg_color = Color(0.85, 0.2, 0.2, 0.95)
	else:
		st.bg_color = Color(0.12, 0.16, 0.22, 0.95)

	toast.add_theme_stylebox_override("panel", st)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	toast.add_child(lbl)

	add_child(toast)
	toast.position = Vector2((size.x - 320) / 2.0, 24)
	toast.custom_minimum_size = Vector2(320, 0)

	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	tween.tween_callback(toast.queue_free)

func _init_services() -> void:
	if not db:
		var SQLiteDatabaseScript = load("res://src/infrastructure/database/sqlite_database.gd")
		if SQLiteDatabaseScript:
			db = SQLiteDatabaseScript.new()
	if db:
		playlists_svc = PlaylistsServiceScript.new(db)
		oauth_svc = YouTubeOAuthServiceScript.new(db)
		add_child(oauth_svc)
		sync_svc = YouTubePlaylistSyncServiceScript.new(playlists_svc, oauth_svc)
		add_child(sync_svc)

func _apply_input_and_button_rules() -> void:
	var line_edits = [search_library_input, item_search_input]
	for le in line_edits:
		if le:
			le.caret_blink = true
			le.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))

	var btns = [btn_new_playlist, btn_add_song, btn_play_playlist, btn_open_playlist]
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
	normal_st.content_margin_left = 12
	normal_st.content_margin_right = 12
	normal_st.content_margin_top = 6
	normal_st.content_margin_bottom = 6

	var hover_st = normal_st.duplicate()

	if is_danger:
		normal_st.bg_color = Color(0.85, 0.2, 0.2, 1.0)
		hover_st.bg_color = Color(0.95, 0.3, 0.3, 1.0)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	elif is_primary:
		normal_st.bg_color = Color(0.12, 0.65, 0.35, 1.0)
		hover_st.bg_color = Color(0.16, 0.75, 0.40, 1.0)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		normal_st.bg_color = Color(0.94, 0.96, 0.98, 1.0)
		normal_st.border_width_left = 1
		normal_st.border_width_top = 1
		normal_st.border_width_right = 1
		normal_st.border_width_bottom = 1
		normal_st.border_color = Color(0.82, 0.85, 0.90, 1.0)
		hover_st.bg_color = Color(0.88, 0.92, 0.96, 1.0)
		btn.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))

	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1) if (is_primary or is_danger) else Color(0.12, 0.16, 0.22, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn.add_theme_stylebox_override("normal", normal_st)
	btn.add_theme_stylebox_override("hover", hover_st)

func _connect_signals() -> void:
	if btn_new_playlist:
		btn_new_playlist.pressed.connect(_on_create_playlist_pressed)
	if search_library_input:
		search_library_input.text_changed.connect(_on_search_library_changed)
	if item_search_input:
		item_search_input.text_changed.connect(_on_search_items_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed() and event.keycode == KEY_V:
			var focus_owner = get_viewport().gui_get_focus_owner()
			if focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is CodeEdit:
				return
			_on_paste_url_pressed()
			get_viewport().set_input_as_handled()

func _on_paste_url_pressed() -> void:
	if current_playlist_id.is_empty(): return
	var clip = DisplayServer.clipboard_get().strip_edges()
	if clip.is_empty():
		_show_invalid_url_notification("Clipboard is empty.")
		return
	var val = playlists_svc.validate_and_extract_url(clip)
	if not val["is_valid"]:
		_show_invalid_url_notification("No valid media URL found in clipboard.")
		return
	_process_dropped_url_or_file(clip, current_playlist_id, _get_target_insert_index())

func _get_target_insert_index() -> int:
	if selected_song_item_id.is_empty():
		return items_list.size()
	for i in range(items_list.size()):
		if str(items_list[i].get("id", "")) == selected_song_item_id:
			return i + 1
	return items_list.size()

func _check_clipboard_on_focus() -> void:
	if current_playlist_id.is_empty() or not playlists_svc: return
	var clip = DisplayServer.clipboard_get().strip_edges()
	if clip == _last_detected_clip_url: return
	_last_detected_clip_url = clip

	var val = playlists_svc.validate_and_extract_url(clip)
	if val["is_valid"]:
		_show_clipboard_banner(clip, val)

func _show_clipboard_banner(clip_url: String, meta: Dictionary) -> void:
	if clipboard_banner_panel and is_instance_valid(clipboard_banner_panel):
		clipboard_banner_panel.queue_free()

	clipboard_banner_panel = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.92, 0.96, 1.0, 1.0)
	st.border_width_left = 4
	st.border_color = Color(0.12, 0.65, 0.35, 1.0)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	clipboard_banner_panel.add_theme_stylebox_override("panel", st)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var title_str = str(meta.get("title", "YouTube Song"))
	var lbl = Label.new()
	lbl.text = "📋 Found Link in Clipboard: “" + title_str + "”"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	hbox.add_child(lbl)

	var btn_add = Button.new()
	btn_add.text = "+ Add to Playlist"
	_style_button(btn_add, true)
	btn_add.pressed.connect(func():
		if clipboard_banner_panel: clipboard_banner_panel.queue_free()
		_process_dropped_url_or_file(clip_url, current_playlist_id, _get_target_insert_index())
	)
	hbox.add_child(btn_add)

	var btn_ignore = Button.new()
	btn_ignore.text = "Dismiss"
	_style_button(btn_ignore)
	btn_ignore.pressed.connect(func():
		if clipboard_banner_panel: clipboard_banner_panel.queue_free()
	)
	hbox.add_child(btn_ignore)

	clipboard_banner_panel.add_child(hbox)
	detail_vbox.add_child(clipboard_banner_panel)
	detail_vbox.move_child(clipboard_banner_panel, 1)

func _extract_url_from_data(data: Variant) -> String:
	if typeof(data) == TYPE_STRING:
		var s = (data as String).strip_edges()
		if s.begins_with("http://") or s.begins_with("https://") or s.begins_with("file://"):
			return s
	elif typeof(data) == TYPE_DICTIONARY:
		var u = str(data.get("url", "")).strip_edges()
		if u != "": return u
	elif typeof(data) == TYPE_PACKED_STRING_ARRAY:
		var arr = data as PackedStringArray
		if arr.size() > 0:
			return arr[0].strip_edges()
	return ""

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
	if playlists_vbox:
		for c in playlists_vbox.get_children():
			if c is PlaylistDropSlotControl: c._update_style(false)
	if items_vbox:
		for c in items_vbox.get_children():
			if c is SongDropSlotControl: c._update_style(false)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if current_playlist_id.is_empty(): return false
	var url_str = _extract_url_from_data(data)
	if url_str != "": return true
	if typeof(data) == TYPE_DICTIONARY:
		var t = data.get("type")
		if t == "song_item" or t == "playlist":
			return true
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	clear_all_drop_slots()
	var url_str = _extract_url_from_data(data)
	if url_str != "":
		_process_dropped_url_or_file(url_str, current_playlist_id, items_list.size())

func load_playlists(select_id: String = "") -> void:
	if not playlists_svc: return
	playlists_list = playlists_svc.get_all_playlists()

	if playlists_list.size() > 0:
		if select_id != "" and _playlist_exists(select_id):
			select_playlist(select_id)
		elif current_playlist_id != "" and _playlist_exists(current_playlist_id):
			select_playlist(current_playlist_id)
		else:
			select_playlist(str(playlists_list[0].get("id", "")))
	else:
		current_playlist_id = ""
		_render_playlists_list()
		_render_selected_playlist_header({})
		load_playlist_items()

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
		if btn_add_song: btn_add_song.disabled = true
		if btn_play_playlist: btn_play_playlist.disabled = true
		if btn_open_playlist: btn_open_playlist.disabled = true
		if btn_header_overflow: btn_header_overflow.disabled = true
		if provider_badge_lbl: provider_badge_lbl.visible = false
		if sync_badge_lbl: sync_badge_lbl.visible = false
	else:
		var p_name = str(pl.get("name", "Untitled"))
		var desc = str(pl.get("description", "")).strip_edges()
		var count = int(pl.get("item_count", 0))

		selected_playlist_title.text = p_name

		var link = playlists_svc.get_playlist_provider_link(current_playlist_id, "youtube") if playlists_svc else {}
		var ext_id = str(link.get("external_playlist_id", ""))
		var sync_status = str(link.get("sync_status", "not_synced"))

		var meta_text = str(count) + (" song" if count == 1 else " songs")
		if not ext_id.is_empty():
			var ch_name = "RealLife House"
			if oauth_svc and oauth_svc.has_method("get_account_status"):
				ch_name = str(oauth_svc.get_account_status().get("channel_title", "RealLife House"))
			meta_text += " • " + ch_name + " • Unlisted"
		elif desc != "":
			meta_text += " • " + desc

		selected_playlist_meta.text = meta_text

		if provider_badge_lbl:
			provider_badge_lbl.visible = true
			if not ext_id.is_empty():
				provider_badge_lbl.text = "YOUTUBE"
				var b_st = StyleBoxFlat.new()
				b_st.bg_color = Color(0.85, 0.15, 0.15, 1.0)
				b_st.content_margin_left = 6; b_st.content_margin_right = 6; b_st.content_margin_top = 2; b_st.content_margin_bottom = 2
				b_st.corner_radius_top_left = 4; b_st.corner_radius_top_right = 4; b_st.corner_radius_bottom_left = 4; b_st.corner_radius_bottom_right = 4
				provider_badge_lbl.add_theme_stylebox_override("panel", b_st)
			else:
				provider_badge_lbl.text = "LOCAL"
				var b_st = StyleBoxFlat.new()
				b_st.bg_color = Color(0.45, 0.50, 0.58, 1.0)
				b_st.content_margin_left = 6; b_st.content_margin_right = 6; b_st.content_margin_top = 2; b_st.content_margin_bottom = 2
				b_st.corner_radius_top_left = 4; b_st.corner_radius_top_right = 4; b_st.corner_radius_bottom_left = 4; b_st.corner_radius_bottom_right = 4
				provider_badge_lbl.add_theme_stylebox_override("panel", b_st)

		if sync_badge_lbl:
			if not ext_id.is_empty():
				sync_badge_lbl.visible = true
				match sync_status:
					"syncing":
						sync_badge_lbl.text = "⟳ Syncing…"
						sync_badge_lbl.add_theme_color_override("font_color", Color(0.2, 0.5, 0.9, 1.0))
					"changes_not_synced":
						sync_badge_lbl.text = "● Changes not synced"
						sync_badge_lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 0.1, 1.0))
					"sync_error":
						sync_badge_lbl.text = "⚠ Sync failed — Retry"
						sync_badge_lbl.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2, 1.0))
					_:
						sync_badge_lbl.text = "✓ Synced"
						sync_badge_lbl.add_theme_color_override("font_color", Color(0.12, 0.65, 0.35, 1.0))
			else:
				sync_badge_lbl.visible = false

		if btn_add_song: btn_add_song.disabled = false
		if btn_play_playlist: btn_play_playlist.disabled = false
		if btn_open_playlist: btn_open_playlist.disabled = false
		if btn_header_overflow: btn_header_overflow.disabled = false

# ==============================================================================
# PLAYLIST ITEMS UI
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
	playlists_svc.reorder_playlist_item(current_playlist_id, item_id, target_index)
	load_playlist_items()
	_trigger_auto_sync(current_playlist_id)

func _get_source_badge_color(st: String) -> Color:
	match st:
		"youtube": return Color(0.85, 0.15, 0.15, 1.0)
		"spotify": return Color(0.11, 0.72, 0.33, 1.0)
		"apple_music": return Color(0.95, 0.22, 0.35, 1.0)
		"local_file": return Color(0.25, 0.45, 0.85, 1.0)
		_: return Color(0.45, 0.50, 0.58, 1.0)

func _get_source_icon(st: String) -> String:
	match st:
		"youtube": return "▶"
		"spotify": return "♫"
		"apple_music": return ""
		"local_file": return "📁"
		_: return "🔗"

func _format_duration(seconds: int) -> String:
	if seconds <= 0: return ""
	var mins = seconds / 60
	var secs = seconds % 60
	return "%d:%02d" % [mins, secs]

func _on_files_dropped(files: PackedStringArray) -> void:
	if files.size() == 0: return
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
	_show_temporary_toast(msg, true)

func _show_add_song_dialog() -> void:
	if current_playlist_id.is_empty(): return
	var dialog = Window.new()
	dialog.title = "+ Add Song to Playlist"
	dialog.size = Vector2i(540, 440)
	dialog.exclusive = true
	dialog.unresizable = true

	var close_dialog = func(): dialog.queue_free()
	dialog.close_requested.connect(close_dialog)

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(main_vbox)

	var header_lbl = Label.new()
	header_lbl.text = "Add Music or Video"
	header_lbl.add_theme_font_size_override("font_size", 18)
	header_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	main_vbox.add_child(header_lbl)

	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Tab 1: YouTube Link
	var tab1 = VBoxContainer.new()
	tab1.name = "YouTube URL"
	tab1.add_theme_constant_override("separation", 12)

	var url_lbl = Label.new()
	url_lbl.text = "Paste YouTube Video or Playlist Link:"
	url_lbl.add_theme_font_size_override("font_size", 13)
	tab1.add_child(url_lbl)

	var url_edit = LineEdit.new()
	url_edit.placeholder_text = "https://www.youtube.com/watch?v=..."
	url_edit.custom_minimum_size = Vector2(0, 36)
	url_edit.caret_blink = true
	url_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	tab1.add_child(url_edit)

	var btn_add_url = Button.new()
	btn_add_url.text = "+ Add YouTube Song"
	_style_button(btn_add_url, true)
	btn_add_url.pressed.connect(func():
		var u = url_edit.text.strip_edges()
		if u != "":
			dialog.queue_free()
			_process_dropped_url_or_file(u, current_playlist_id, -1)
	)
	tab1.add_child(btn_add_url)
	tabs.add_child(tab1)

	# Tab 2: Web or Local File
	var tab2 = VBoxContainer.new()
	tab2.name = "Web / Local File"
	tab2.add_theme_constant_override("separation", 12)

	var web_url_lbl = Label.new()
	web_url_lbl.text = "Enter Media Web URL or Local File Path:"
	tab2.add_child(web_url_lbl)

	var web_url_edit = LineEdit.new()
	web_url_edit.placeholder_text = "https://example.com/audio.mp3 or file:///path/to/song.mp3"
	web_url_edit.custom_minimum_size = Vector2(0, 36)
	web_url_edit.caret_blink = true
	web_url_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	tab2.add_child(web_url_edit)

	var btn_add_web = Button.new()
	btn_add_web.text = "+ Add Media Link"
	_style_button(btn_add_web, true)
	btn_add_web.pressed.connect(func():
		var u = web_url_edit.text.strip_edges()
		if u != "":
			dialog.queue_free()
			_process_dropped_url_or_file(u, current_playlist_id, -1)
	)
	tab2.add_child(btn_add_web)
	tabs.add_child(tab2)

	main_vbox.add_child(tabs)

	var close_hbox = HBoxContainer.new()
	close_hbox.alignment = BoxContainer.ALIGNMENT_END
	var btn_close = Button.new()
	btn_close.text = "Cancel"
	_style_button(btn_close)
	btn_close.pressed.connect(close_dialog)
	close_hbox.add_child(btn_close)
	main_vbox.add_child(close_hbox)

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
					playlists_svc.update_playlist_item(temp_item_id, "YouTube Video (" + vid_id + ")", "", "youtube", canonical_url, "", 0, str(meta.get("thumbnail_url", "")))
					if target_playlist_id == current_playlist_id:
						load_playlist_items()
				_trigger_auto_sync(target_playlist_id)
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
		_trigger_auto_sync(target_playlist_id)

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
	_style_button(btn_remove, false, true)
	btn_remove.pressed.connect(func():
		playlists_svc.delete_playlist_item(item_id)
		dialog.queue_free()
		load_playlist_items()
		_trigger_auto_sync(current_playlist_id)
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

func _on_duplicate_playlist_pressed() -> void:
	if current_playlist_id.is_empty(): return
	var pl = playlists_svc.get_playlist_by_id(current_playlist_id)
	var new_id = playlists_svc.duplicate_playlist(current_playlist_id, str(pl.get("name", "Playlist")) + " (Copy)")
	load_playlists(new_id)
	_show_temporary_toast("✓ Duplicated playlist locally")

func _on_delete_playlist_pressed() -> void:
	if current_playlist_id.is_empty(): return
	var pl = playlists_svc.get_playlist_by_id(current_playlist_id)
	var pl_name = str(pl.get("name", "Playlist"))

	var dialog = Window.new()
	dialog.title = "Delete Playlist"
	dialog.size = Vector2i(440, 180)
	dialog.exclusive = true
	dialog.unresizable = true

	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.add_theme_constant_override("margin_left", 20); margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20); margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var msg_lbl = Label.new()
	msg_lbl.text = "Are you sure you want to delete “" + pl_name + "”?\nThis operation cannot be undone."
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg_lbl.add_theme_font_size_override("font_size", 14)
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
	btn_del.text = "Delete"
	_style_button(btn_del, false, true)
	btn_del.pressed.connect(func():
		var del_id = current_playlist_id
		playlists_svc.delete_playlist(del_id)
		dialog.queue_free()
		load_playlists()
		_show_temporary_toast("Deleted playlist")
	)
	btn_hbox.add_child(btn_del)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

func _show_playlist_dialog(existing_pl: Dictionary = {}) -> void:
	var dialog = Window.new()
	dialog.title = "Edit Playlist" if not existing_pl.is_empty() else "Create New Playlist"
	dialog.size = Vector2i(450, 360)
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
	desc_lbl.text = "Description (Optional):"
	vbox.add_child(desc_lbl)

	var desc_edit = TextEdit.new()
	desc_edit.text = str(existing_pl.get("description", ""))
	desc_edit.placeholder_text = "Add playlist notes or details..."
	desc_edit.custom_minimum_size = Vector2(0, 100)
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
		var new_name = name_edit.text.strip_edges()
		var new_desc = desc_edit.text.strip_edges()
		if not new_name.is_empty():
			if existing_pl.is_empty():
				var new_id = playlists_svc.create_playlist(new_name, new_desc)
				load_playlists(new_id)
			else:
				var pl_id = str(existing_pl.get("id", ""))
				playlists_svc.update_playlist(pl_id, new_name, new_desc)
				load_playlists(pl_id)
				_trigger_auto_sync(pl_id)
			dialog.queue_free()
	)
	btn_hbox.add_child(btn_save)

	vbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

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
			label.text = "──────── Drop here ────────"
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
			label.text = "──────── Drop here ────────"
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

		var drag_handle = Label.new()
		drag_handle.text = "⠿"
		drag_handle.tooltip_text = "Drag to reorder playlist"
		drag_handle.add_theme_font_size_override("font_size", 14)
		drag_handle.add_theme_color_override("font_color", Color(0.60, 0.65, 0.72, 1.0))
		hbox.add_child(drag_handle)

		var name_vbox = VBoxContainer.new()
		name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl = Label.new()
		name_lbl.text = p_name
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
		name_vbox.add_child(name_lbl)

		var link = view_ref.playlists_svc.get_playlist_provider_link(playlist_id, "youtube") if view_ref.playlists_svc else {}
		var ext_id = str(link.get("external_playlist_id", ""))
		var provider_str = "YouTube" if not ext_id.is_empty() else "General"
		var sync_status = str(link.get("sync_status", "synced"))

		var meta_lbl = Label.new()
		meta_lbl.text = provider_str + " • " + str(p_count) + (" song" if p_count == 1 else " songs")
		meta_lbl.add_theme_font_size_override("font_size", 11)
		meta_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62, 1.0))
		name_vbox.add_child(meta_lbl)

		hbox.add_child(name_vbox)

		if not ext_id.is_empty():
			var status_icon = Label.new()
			match sync_status:
				"syncing":
					status_icon.text = "⟳"
					status_icon.add_theme_color_override("font_color", Color(0.2, 0.5, 0.9, 1.0))
				"changes_not_synced":
					status_icon.text = "●"
					status_icon.add_theme_color_override("font_color", Color(0.85, 0.55, 0.1, 1.0))
				"sync_error":
					status_icon.text = "⚠"
					status_icon.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2, 1.0))
				_:
					status_icon.text = "✓"
					status_icon.add_theme_color_override("font_color", Color(0.12, 0.65, 0.35, 1.0))
			status_icon.add_theme_font_size_override("font_size", 13)
			hbox.add_child(status_icon)

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
			card_st.border_color = Color(0.12, 0.65, 0.35, 1.0)
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
		st.bg_color = Color(0.12, 0.65, 0.35, 0.95)
		st.corner_radius_top_left = 6
		st.corner_radius_top_right = 6
		st.corner_radius_bottom_left = 6
		st.corner_radius_bottom_right = 6
		st.content_margin_left = 14; st.content_margin_right = 14; st.content_margin_top = 8; st.content_margin_bottom = 8
		st.shadow_color = Color(0, 0, 0, 0.3)
		st.shadow_size = 8
		preview.add_theme_stylebox_override("panel", st)

		var lbl = Label.new()
		lbl.text = "🎵 " + playlist_name
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.add_theme_font_size_override("font_size", 14)
		preview.add_child(lbl)
		return preview

	func _show_context_menu(target_control: Control) -> void:
		var popup = PopupMenu.new()
		popup.add_item("✏️ Edit Name/Desc", 1)
		popup.add_item("📋 Duplicate Playlist", 2)

		var link = view_ref.playlists_svc.get_playlist_provider_link(playlist_id, "youtube") if view_ref.playlists_svc else {}
		var ext_id = str(link.get("external_playlist_id", ""))
		if not ext_id.is_empty():
			popup.add_item("📋 Copy YouTube Link", 3)
			popup.add_item("🔄 Sync Now", 4)

		popup.add_separator()
		popup.add_item("🗑️ Delete Playlist", 5)

		popup.id_pressed.connect(func(id: int):
			match id:
				1:
					var pl = view_ref.playlists_svc.get_playlist_by_id(playlist_id)
					view_ref._show_playlist_dialog(pl)
				2:
					var pl = view_ref.playlists_svc.get_playlist_by_id(playlist_id)
					var new_id = view_ref.playlists_svc.duplicate_playlist(playlist_id, str(pl.get("name", "Playlist")) + " (Copy)")
					view_ref.load_playlists(new_id)
					view_ref._show_temporary_toast("✓ Duplicated playlist locally")
				3:
					var ext_url = str(link.get("external_playlist_url", ""))
					if not ext_url.is_empty():
						DisplayServer.clipboard_set(ext_url)
						view_ref._show_temporary_toast("✓ Copied YouTube playlist link to clipboard")
				4:
					view_ref._trigger_auto_sync(playlist_id)
				5:
					view_ref.current_playlist_id = playlist_id
					view_ref._on_delete_playlist_pressed()
			popup.queue_free()
		)
		popup.popup_hide.connect(func(): popup.queue_free())
		target_control.add_child(popup)
		popup.popup(Rect2i(Vector2i(target_control.global_position), Vector2i(200, 150)))

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
		var dur_sec = int(item_data.get("duration_seconds", 0))

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)

		# Index & Drag handle ⠿
		var drag_handle = Label.new()
		drag_handle.text = "⠿  " + str(item_index + 1)
		drag_handle.tooltip_text = "Drag to reorder song"
		drag_handle.custom_minimum_size = Vector2(36, 0)
		drag_handle.add_theme_font_size_override("font_size", 13)
		drag_handle.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68, 1.0))
		hbox.add_child(drag_handle)

		# Video Thumbnail Picture Frame
		var thumb_frame = PanelContainer.new()
		thumb_frame.custom_minimum_size = Vector2(72, 42)
		thumb_frame.clip_contents = true
		var tf_st = StyleBoxFlat.new()
		tf_st.bg_color = view_ref._get_source_badge_color(source_type)
		tf_st.corner_radius_top_left = 6
		tf_st.corner_radius_top_right = 6
		tf_st.corner_radius_bottom_left = 6
		tf_st.corner_radius_bottom_right = 6
		thumb_frame.add_theme_stylebox_override("panel", tf_st)

		_thumb_rect = TextureRect.new()
		_thumb_rect.custom_minimum_size = Vector2(72, 42)
		_thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb_frame.add_child(_thumb_rect)

		_fallback_lbl = Label.new()
		_fallback_lbl.text = view_ref._get_source_icon(source_type)
		_fallback_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fallback_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_fallback_lbl.add_theme_font_size_override("font_size", 14)
		_fallback_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		thumb_frame.add_child(_fallback_lbl)
		hbox.add_child(thumb_frame)

		_thumb_url = str(item_data.get("thumbnail_url", ""))
		if _thumb_url == "" and source_type == "youtube":
			var vid_id = view_ref.playlists_svc.extract_youtube_video_id(url)
			if vid_id != "":
				_thumb_url = "https://i.ytimg.com/vi/" + vid_id + "/hqdefault.jpg"

		# Main Info VBox with crisp text autowrapping
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

		# Action buttons
		var actions_hbox = HBoxContainer.new()
		actions_hbox.add_theme_constant_override("separation", 6)

		if url != "":
			var btn_play = Button.new()
			btn_play.text = "▶ Play"
			btn_play.tooltip_text = "Play on YouTube starting from this song"
			btn_play.pressed.connect(func():
				if view_ref and view_ref.sync_svc:
					view_ref.sync_svc.open_play_from_here_in_browser(item_id)
				elif url != "":
					OS.shell_open(url)
			)
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
			card_st.border_color = Color(0.12, 0.65, 0.35, 1.0)

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
		st.bg_color = Color(0.12, 0.65, 0.35, 0.95)
		st.corner_radius_top_left = 6
		st.corner_radius_top_right = 6
		st.corner_radius_bottom_left = 6
		st.corner_radius_bottom_right = 6
		st.content_margin_left = 14; st.content_margin_right = 14; st.content_margin_top = 8; st.content_margin_bottom = 8
		st.shadow_color = Color(0, 0, 0, 0.3)
		st.shadow_size = 8
		preview.add_theme_stylebox_override("panel", st)

		var lbl = Label.new()
		lbl.text = "🎵 " + str(item_data.get("title", "Song"))
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.add_theme_font_size_override("font_size", 14)
		preview.add_child(lbl)
		return preview

	func _show_options_menu(target_control: Control) -> void:
		var popup = PopupMenu.new()
		popup.add_item("▶ Play on YouTube", 1)
		popup.add_item("📋 Copy Song Link", 2)
		popup.add_item("✏️ Edit Metadata", 3)
		popup.add_separator()
		popup.add_item("🗑️ Remove from Playlist", 4)

		var url = str(item_data.get("url", ""))

		popup.id_pressed.connect(func(id: int):
			match id:
				1:
					if view_ref and view_ref.sync_svc:
						view_ref.sync_svc.open_play_from_here_in_browser(item_id)
					elif url != "":
						OS.shell_open(url)
				2:
					if url != "":
						DisplayServer.clipboard_set(url)
						view_ref._show_temporary_toast("✓ Copied song URL to clipboard")
				3:
					view_ref._show_add_edit_item_dialog(item_data)
				4:
					var pl = view_ref.playlists_svc.get_playlist_by_id(view_ref.current_playlist_id)
					var pl_name = str(pl.get("name", "Playlist"))
					view_ref._show_remove_song_confirmation(item_id, item_data, pl_name)
			popup.queue_free()
		)
		popup.popup_hide.connect(func(): popup.queue_free())
		target_control.add_child(popup)
		popup.popup(Rect2i(Vector2i(target_control.global_position), Vector2i(200, 140)))

class EmptyPlaylistControl extends PanelContainer:
	var view_ref: Control
	var playlist_id: String

	func _init(p_view: Control, p_id: String) -> void:
		view_ref = p_view
		playlist_id = p_id
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CAN_DROP

		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.96, 0.98, 1.0, 1.0)
		st.border_width_left = 2; st.border_width_top = 2; st.border_width_right = 2; st.border_width_bottom = 2
		st.border_color = Color(0.82, 0.88, 0.95, 1.0)
		st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
		st.content_margin_left = 24; st.content_margin_top = 24; st.content_margin_right = 24; st.content_margin_bottom = 24
		add_theme_stylebox_override("panel", st)

		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 10)

		var lbl_title = Label.new()
		lbl_title.text = "🎵 Playlist is Empty"
		lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_title.add_theme_font_size_override("font_size", 16)
		lbl_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
		vbox.add_child(lbl_title)

		var lbl_desc = Label.new()
		lbl_desc.text = "Click '+ ADD SONG' above or drag a YouTube link directly into this playlist."
		lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_desc.add_theme_font_size_override("font_size", 13)
		lbl_desc.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58, 1.0))
		vbox.add_child(lbl_desc)

		var btn_add = Button.new()
		btn_add.text = "+ Add Song"
		btn_add.custom_minimum_size = Vector2(130, 34)
		view_ref._style_button(btn_add, true)
		btn_add.pressed.connect(func():
			view_ref._show_add_song_dialog()
		)
		vbox.add_child(btn_add)

		add_child(vbox)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		var url_str = view_ref._extract_url_from_data(data)
		if url_str != "":
			view_ref.set_active_song_drop_slot(0)
			return true
		return false

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		view_ref.clear_all_drop_slots()
		var url_str = view_ref._extract_url_from_data(data)
		if url_str != "":
			view_ref._process_dropped_url_or_file(url_str, playlist_id, 0)
