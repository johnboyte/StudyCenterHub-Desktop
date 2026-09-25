extends "res://app/scenes/standard_page_container.gd"

## Platform Settings & Google Workspace Sync Center Controller (SYNC-SPR1-001)
## Complies with [PD-001] (Customer Data Ownership & Outbox Pattern) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const GoogleWorkspaceSyncWorkerScript = preload("res://src/infrastructure/sync/google_workspace_sync_worker.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			sync_worker = GoogleWorkspaceSyncWorkerScript.new(db)
			_refresh_sync_status()

var sync_worker: RefCounted
var oauth_svc: Node = null

@onready var status_pill: Label = $MarginContainer/MainVBox/SyncCard/SyncMargin/SyncVBox/StatusHBox/StatusPill
@onready var queue_pill: Label = $MarginContainer/MainVBox/SyncCard/SyncMargin/SyncVBox/StatusHBox/QueuePill
@onready var btn_sync_now: Button = $MarginContainer/MainVBox/SyncCard/SyncMargin/SyncVBox/StatusHBox/BtnSyncNow
@onready var credentials_card: PanelContainer = $MarginContainer/MainVBox/CredentialsCard
@onready var youtube_card: PanelContainer = $MarginContainer/MainVBox/YouTubeCard
@onready var outbox_log_card: PanelContainer = $MarginContainer/MainVBox/OutboxLogCard

func _ready() -> void:
	_init_database()
	_init_oauth_service()
	_style_cards()
	_populate_credentials_card()
	_populate_youtube_card()
	_connect_signals()
	_refresh_sync_status()

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
	if not sync_worker:
		sync_worker = GoogleWorkspaceSyncWorkerScript.new(db)

func _init_oauth_service() -> void:
	if not oauth_svc:
		var app_shell = get_tree().get_first_node_in_group("app_shell")
		if app_shell and app_shell.has_method("get_oauth_service") and app_shell.get_oauth_service():
			oauth_svc = app_shell.get_oauth_service()
		else:
			oauth_svc = YouTubeOAuthServiceScript.new(db)
			add_child(oauth_svc)

	if oauth_svc:
		if not oauth_svc.auth_completed.is_connected(_on_oauth_completed):
			oauth_svc.auth_completed.connect(_on_oauth_completed)
		if not oauth_svc.auth_disconnected.is_connected(_on_oauth_disconnected):
			oauth_svc.auth_disconnected.connect(_on_oauth_disconnected)

func _on_oauth_completed(_success: bool, _err: String) -> void:
	_refresh_youtube_card()

func _on_oauth_disconnected() -> void:
	_refresh_youtube_card()

func _style_cards() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.91, 0.95, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 18
	style.content_margin_top = 16
	style.content_margin_right = 18
	style.content_margin_bottom = 16
	credentials_card.add_theme_stylebox_override("panel", style)
	youtube_card.add_theme_stylebox_override("panel", style.duplicate())
	outbox_log_card.add_theme_stylebox_override("panel", style.duplicate())

	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = _get_active_theme_color()
	btn_st.corner_radius_top_left = 6
	btn_st.corner_radius_top_right = 6
	btn_st.corner_radius_bottom_left = 6
	btn_st.corner_radius_bottom_right = 6
	btn_sync_now.add_theme_stylebox_override("normal", btn_st)
	btn_sync_now.add_theme_stylebox_override("hover", btn_st)
	btn_sync_now.add_theme_stylebox_override("pressed", btn_st)

func _get_active_theme_color() -> Color:
	var idx = 0
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "0"))

	if idx == 0:
		return Color(0.596, 0.192, 0.255, 1.0) # AU Crimson Red #983141
	elif idx == 1:
		return Color(0.88, 0.35, 0.21, 1.0) # Warm Terracotta #E05A36
	elif idx == 2:
		return Color(0.10, 0.15, 0.21, 1.0) # Deep Navy #1A2536
	elif idx == 3:
		return Color(0.18, 0.49, 0.20, 1.0) # Forest Green #2E7D32
	elif idx == 4:
		return Color(0.42, 0.11, 0.60, 1.0) # Royal Purple #6A1B9A
	return Color(0.596, 0.192, 0.255, 1.0)

func _connect_signals() -> void:
	if btn_sync_now and not btn_sync_now.pressed.is_connected(_on_sync_now_pressed):
		btn_sync_now.pressed.connect(_on_sync_now_pressed)

func _populate_credentials_card() -> void:
	for child in credentials_card.get_children(): child.free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var title_lbl = Label.new()
	title_lbl.text = "Customer-Owned Google Workspace API Credentials (PD-001)"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Enter your organization's Google Service Account key and target Google Sheets / Drive IDs to enable automatic outbox sync."
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.68, 1.0))
	vbox.add_child(sub_lbl)

	var form_vbox = VBoxContainer.new()
	form_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	form_vbox.add_theme_constant_override("separation", 6)

	var l1 = Label.new()
	l1.text = "Google Service Account Email"
	l1.add_theme_font_size_override("font_size", 13)
	l1.add_theme_color_override("font_color", Color(0.25, 0.32, 0.42, 1.0))
	form_vbox.add_child(l1)

	var e1 = LineEdit.new()
	e1.text = "studycenter-sync@appspot.gserviceaccount.com"
	e1.custom_minimum_size = Vector2(0, 38)
	e1.size_flags_horizontal = SIZE_EXPAND_FILL
	e1.caret_blink = true
	e1.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	form_vbox.add_child(e1)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	form_vbox.add_child(spacer)

	var l2 = Label.new()
	l2.text = "Target Google Sheet or Drive ID"
	l2.add_theme_font_size_override("font_size", 13)
	l2.add_theme_color_override("font_color", Color(0.25, 0.32, 0.42, 1.0))
	form_vbox.add_child(l2)

	var e2 = LineEdit.new()
	e2.text = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"
	e2.custom_minimum_size = Vector2(0, 38)
	e2.size_flags_horizontal = SIZE_EXPAND_FILL
	e2.caret_blink = true
	e2.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	form_vbox.add_child(e2)

	vbox.add_child(form_vbox)
	credentials_card.add_child(vbox)

var _is_replacing_client_secret: bool = false
var _client_id_feedback_msg: String = ""
var _client_secret_feedback_msg: String = ""

# --- PLAYLIST PROVIDERS — YouTube Card ---
func _populate_youtube_card() -> void:
	if not youtube_card: return
	_refresh_youtube_card()

func _refresh_youtube_card() -> void:
	if not youtube_card: return
	for child in youtube_card.get_children(): child.queue_free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Section Header
	var section_lbl = Label.new()
	section_lbl.text = "PLAYLIST PROVIDERS"
	section_lbl.add_theme_font_size_override("font_size", 11)
	section_lbl.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62, 1.0))
	vbox.add_child(section_lbl)

	# Provider Sub-Header
	var title_lbl = Label.new()
	title_lbl.text = "YouTube"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_lbl)

	var current_cid = oauth_svc.get_client_id() if oauth_svc else ""
	var has_secret = oauth_svc.has_client_secret() if oauth_svc else false
	var has_cid = not current_cid.is_empty()
	var is_configured = oauth_svc.is_configured() if oauth_svc else false
	var status_info = oauth_svc.get_account_status() if oauth_svc else {"connected": false}
	var is_connected = status_info.get("connected", false)

	# Status Label
	var status_lbl = Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.add_theme_font_size_override("font_size", 14)

	if not has_cid and not has_secret:
		status_lbl.text = "Status: YouTube setup required (Client ID & Client Secret required)"
		status_lbl.add_theme_color_override("font_color", Color(0.88, 0.55, 0.21, 1.0)) # Orange/Warning
	elif not has_cid:
		status_lbl.text = "Status: YouTube setup required (Client ID required)"
		status_lbl.add_theme_color_override("font_color", Color(0.88, 0.55, 0.21, 1.0)) # Orange/Warning
	elif not has_secret:
		status_lbl.text = "Status: YouTube setup required (Client Secret required)"
		status_lbl.add_theme_color_override("font_color", Color(0.88, 0.55, 0.21, 1.0)) # Orange/Warning
	elif is_connected:
		var ch_title = str(status_info.get("channel_title", "Connected Account"))
		status_lbl.text = "Status: Connected to " + ch_title
		status_lbl.add_theme_color_override("font_color", Color(0.06, 0.72, 0.51, 1.0)) # Green
	else:
		status_lbl.text = "Status: Not Connected"
		status_lbl.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62, 1.0)) # Muted grey
	vbox.add_child(status_lbl)

	# Client ID Label & Form Row
	var cid_lbl = Label.new()
	cid_lbl.text = "Google OAuth Client ID:"
	cid_lbl.add_theme_font_size_override("font_size", 13)
	cid_lbl.add_theme_color_override("font_color", Color(0.25, 0.32, 0.42, 1.0))
	vbox.add_child(cid_lbl)

	var cid_hbox = HBoxContainer.new()
	cid_hbox.add_theme_constant_override("separation", 10)

	var cid_edit = LineEdit.new()
	cid_edit.name = "ClientIDEdit"
	cid_edit.text = current_cid
	cid_edit.placeholder_text = "e.g., 1234567890-abcdef.apps.googleusercontent.com"
	cid_edit.custom_minimum_size = Vector2(0, 38)
	cid_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	cid_edit.caret_blink = true
	cid_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	cid_hbox.add_child(cid_edit)

	var btn_save_id = Button.new()
	btn_save_id.name = "BtnSaveClientID"
	btn_save_id.text = "Save"
	btn_save_id.custom_minimum_size = Vector2(90, 38)
	_style_settings_button(btn_save_id, true, false)
	btn_save_id.pressed.connect(func(): _on_save_client_id_pressed(cid_edit))
	cid_hbox.add_child(btn_save_id)
	vbox.add_child(cid_hbox)

	if not _client_id_feedback_msg.is_empty():
		var fb_lbl = Label.new()
		fb_lbl.text = _client_id_feedback_msg
		fb_lbl.add_theme_font_size_override("font_size", 12)
		if "✓" in _client_id_feedback_msg:
			fb_lbl.add_theme_color_override("font_color", Color(0.06, 0.72, 0.51, 1.0))
		else:
			fb_lbl.add_theme_color_override("font_color", Color(0.85, 0.22, 0.22, 1.0))
		vbox.add_child(fb_lbl)

	# Client Secret Label & Form / Status Row
	var secret_lbl = Label.new()
	secret_lbl.text = "Google OAuth Client Secret:"
	secret_lbl.add_theme_font_size_override("font_size", 13)
	secret_lbl.add_theme_color_override("font_color", Color(0.25, 0.32, 0.42, 1.0))
	vbox.add_child(secret_lbl)

	var secret_hbox = HBoxContainer.new()
	secret_hbox.add_theme_constant_override("separation", 10)

	if has_secret and not _is_replacing_client_secret:
		var saved_info_lbl = Label.new()
		saved_info_lbl.text = "Client Secret: Saved securely in macOS Keychain"
		saved_info_lbl.custom_minimum_size = Vector2(0, 38)
		saved_info_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		saved_info_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		saved_info_lbl.add_theme_font_size_override("font_size", 13)
		saved_info_lbl.add_theme_color_override("font_color", Color(0.06, 0.72, 0.51, 1.0)) # Green
		secret_hbox.add_child(saved_info_lbl)

		var btn_replace_secret = Button.new()
		btn_replace_secret.text = "Replace"
		btn_replace_secret.custom_minimum_size = Vector2(90, 38)
		_style_settings_button(btn_replace_secret, false, false)
		btn_replace_secret.pressed.connect(func():
			_is_replacing_client_secret = true
			_client_secret_feedback_msg = ""
			_refresh_youtube_card()
		)
		secret_hbox.add_child(btn_replace_secret)

		var btn_remove_secret = Button.new()
		btn_remove_secret.text = "Remove"
		btn_remove_secret.custom_minimum_size = Vector2(90, 38)
		_style_settings_button(btn_remove_secret, false, true)
		btn_remove_secret.pressed.connect(func():
			if oauth_svc:
				oauth_svc.remove_client_secret()
			_is_replacing_client_secret = false
			_client_secret_feedback_msg = "Removed Client Secret from Keychain."
			_refresh_youtube_card()
		)
		secret_hbox.add_child(btn_remove_secret)
		vbox.add_child(secret_hbox)

		if not _client_secret_feedback_msg.is_empty():
			var fb_s_lbl = Label.new()
			fb_s_lbl.text = _client_secret_feedback_msg
			fb_s_lbl.add_theme_font_size_override("font_size", 12)
			if "✓" in _client_secret_feedback_msg:
				fb_s_lbl.add_theme_color_override("font_color", Color(0.06, 0.72, 0.51, 1.0))
			else:
				fb_s_lbl.add_theme_color_override("font_color", Color(0.85, 0.22, 0.22, 1.0))
			vbox.add_child(fb_s_lbl)
	else:
		var secret_edit = LineEdit.new()
		secret_edit.name = "ClientSecretEdit"
		secret_edit.secret = true
		secret_edit.placeholder_text = "e.g., GOCSPX-..."
		secret_edit.custom_minimum_size = Vector2(0, 38)
		secret_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		secret_edit.caret_blink = true
		secret_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
		secret_hbox.add_child(secret_edit)

		var btn_save_secret = Button.new()
		btn_save_secret.name = "BtnSaveClientSecret"
		btn_save_secret.text = "Save"
		btn_save_secret.custom_minimum_size = Vector2(90, 38)
		_style_settings_button(btn_save_secret, true, false)
		btn_save_secret.pressed.connect(func(): _on_save_client_secret_pressed(secret_edit))
		secret_hbox.add_child(btn_save_secret)

		if has_secret and _is_replacing_client_secret:
			var btn_cancel_replace = Button.new()
			btn_cancel_replace.text = "Cancel"
			btn_cancel_replace.custom_minimum_size = Vector2(90, 38)
			_style_settings_button(btn_cancel_replace, false, false)
			btn_cancel_replace.pressed.connect(func():
				_is_replacing_client_secret = false
				_client_secret_feedback_msg = ""
				_refresh_youtube_card()
			)
			secret_hbox.add_child(btn_cancel_replace)

		vbox.add_child(secret_hbox)

		if not _client_secret_feedback_msg.is_empty():
			var fb_s_lbl = Label.new()
			fb_s_lbl.text = _client_secret_feedback_msg
			fb_s_lbl.add_theme_font_size_override("font_size", 12)
			if "✓" in _client_secret_feedback_msg:
				fb_s_lbl.add_theme_color_override("font_color", Color(0.06, 0.72, 0.51, 1.0))
			else:
				fb_s_lbl.add_theme_color_override("font_color", Color(0.85, 0.22, 0.22, 1.0))
			vbox.add_child(fb_s_lbl)

	# Action Buttons (Connect / Disconnect)
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 12)

	if is_configured and not is_connected:
		var btn_connect = Button.new()
		btn_connect.text = "Connect YouTube"
		btn_connect.custom_minimum_size = Vector2(180, 38)
		_style_settings_button(btn_connect, true, false)
		btn_connect.pressed.connect(func():
			if oauth_svc:
				var res = oauth_svc.start_authorization_flow()
				if not res.get("success", false):
					var err_msg = str(res.get("error", "Flow failed"))
					status_lbl.text = "Status: ✕ " + err_msg
					status_lbl.add_theme_color_override("font_color", Color(0.85, 0.22, 0.22, 1.0))
		)
		actions_hbox.add_child(btn_connect)
	elif is_connected:
		var btn_disconnect = Button.new()
		btn_disconnect.text = "Disconnect YouTube"
		btn_disconnect.custom_minimum_size = Vector2(180, 38)
		_style_settings_button(btn_disconnect, false, true)
		btn_disconnect.pressed.connect(func():
			if oauth_svc:
				oauth_svc.disconnect_account()
		)
		actions_hbox.add_child(btn_disconnect)

	if actions_hbox.get_child_count() > 0:
		vbox.add_child(actions_hbox)

	youtube_card.add_child(vbox)

func _on_save_client_id_pressed(cid_edit: LineEdit) -> void:
	if not cid_edit: return
	var clean_id = cid_edit.text.strip_edges()
	print("[DIAGNOSTIC] YOUTUBE_CLIENT_ID_SAVE_CLICKED")
	print("[DIAGNOSTIC] client_id_length=", clean_id.length())

	if clean_id.is_empty():
		_client_id_feedback_msg = "⚠️ Client ID cannot be empty."
		print("[DIAGNOSTIC] client_id_save_result=failure_empty")
		_refresh_youtube_card()
		return

	if not oauth_svc:
		_init_oauth_service()

	var success = false
	if oauth_svc:
		success = oauth_svc.set_client_id(clean_id)

	var reloaded = oauth_svc.get_client_id() if oauth_svc else ""
	print("[DIAGNOSTIC] client_id_save_result=", "success" if success else "failure")
	print("[DIAGNOSTIC] client_id_reload_length=", reloaded.length())

	if success and not reloaded.is_empty():
		_client_id_feedback_msg = "✓ Client ID saved"
	else:
		_client_id_feedback_msg = "✕ Failed to save Client ID to database."

	_refresh_youtube_card()

func _on_save_client_secret_pressed(secret_edit: LineEdit) -> void:
	if not secret_edit: return
	var clean_secret = secret_edit.text.strip_edges()
	print("[DIAGNOSTIC] YOUTUBE_CLIENT_SECRET_SAVE_CLICKED")
	print("[DIAGNOSTIC] client_secret_length=", clean_secret.length())

	if clean_secret.is_empty():
		_client_secret_feedback_msg = "⚠️ Client Secret cannot be empty."
		print("[DIAGNOSTIC] client_secret_save_result=failure_empty")
		_refresh_youtube_card()
		return

	if not oauth_svc:
		_init_oauth_service()

	var success = false
	if oauth_svc:
		success = oauth_svc.set_client_secret(clean_secret)

	var present_after = oauth_svc.has_client_secret() if oauth_svc else false
	print("[DIAGNOSTIC] client_secret_save_result=", "success" if success else "failure")
	print("[DIAGNOSTIC] client_secret_present_after_save=", present_after)

	if success and present_after:
		_client_secret_feedback_msg = "✓ Client Secret saved securely in macOS Keychain"
		_is_replacing_client_secret = false
	else:
		_client_secret_feedback_msg = "✕ Failed to save Client Secret to macOS Keychain."

	_refresh_youtube_card()

func _style_settings_button(btn: Button, is_primary: bool = false, is_danger: bool = false) -> void:
	if not btn: return
	var normal_st = StyleBoxFlat.new()
	normal_st.corner_radius_top_left = 6
	normal_st.corner_radius_top_right = 6
	normal_st.corner_radius_bottom_left = 6
	normal_st.corner_radius_bottom_right = 6
	normal_st.content_margin_left = 14
	normal_st.content_margin_right = 14
	normal_st.content_margin_top = 8
	normal_st.content_margin_bottom = 8

	if is_primary:
		normal_st.bg_color = _get_active_theme_color()
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
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1) if (is_primary or is_danger) else Color(0.08, 0.10, 0.15, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1) if (is_primary or is_danger) else Color(0.08, 0.10, 0.15, 1.0))
	btn.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1) if (is_primary or is_danger) else Color(0.08, 0.10, 0.15, 1.0))

func _on_sync_now_pressed() -> void:
	if not db: return
	if not sync_worker: sync_worker = GoogleWorkspaceSyncWorkerScript.new(db)

	var res = sync_worker.process_outbox_batch(100)
	if res["success"]:
		print("Synced ", res["processed_count"], " outbox events to Google Workspace.")
		_refresh_sync_status()

func _refresh_sync_status() -> void:
	if not db: return
	if not sync_worker: sync_worker = GoogleWorkspaceSyncWorkerScript.new(db)

	var pending_events = sync_worker.get_pending_outbox_events()
	queue_pill.text = "Pending Outbox Events: " + str(pending_events.size())

	if pending_events.size() > 0:
		status_pill.text = "🟡 Sync Required (" + str(pending_events.size()) + " pending)"
		status_pill.add_theme_color_override("font_color", Color(0.88, 0.55, 0.21, 1.0))
	else:
		status_pill.text = "🟢 Google Workspace Synced (100%)"
		status_pill.add_theme_color_override("font_color", Color(0.06, 0.72, 0.51, 1.0))

	_refresh_outbox_log()

func _refresh_outbox_log() -> void:
	for child in outbox_log_card.get_children(): child.free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title_lbl = Label.new()
	title_lbl.text = "Google Workspace Outbox Draining Feed (PD-001 Audit Log)"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_lbl)

	var events = sync_worker.get_synced_outbox_events(15)
	if events.size() > 0:
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 240)
		scroll.size_flags_vertical = SIZE_EXPAND_FILL

		var list_vbox = VBoxContainer.new()
		list_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		list_vbox.add_theme_constant_override("separation", 6)

		for evt in events:
			var type_s = str(evt.get("event_type", ""))
			var agg_s = str(evt.get("aggregate_type", ""))
			var sync_s = str(evt.get("processed_at", ""))

			var row = Label.new()
			row.text = "  ✅ Event: " + type_s + " (" + agg_s + ") • Synced to Google Workspace at " + sync_s
			row.add_theme_font_size_override("font_size", 13)
			row.add_theme_color_override("font_color", Color(0.22, 0.28, 0.36, 1.0))
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list_vbox.add_child(row)

		scroll.add_child(list_vbox)
		vbox.add_child(scroll)
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "No outbox events processed yet. Execute action operations to generate outbox events."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(empty_lbl)

	outbox_log_card.add_child(vbox)
