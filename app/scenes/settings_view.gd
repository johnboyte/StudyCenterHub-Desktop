extends "res://app/scenes/standard_page_container.gd"

## Platform Settings & Google Workspace Sync Center Controller (SYNC-SPR1-001)
## Complies with [PD-001] (Customer Data Ownership & Outbox Pattern) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const GoogleWorkspaceSyncWorkerScript = preload("res://src/infrastructure/sync/google_workspace_sync_worker.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			sync_worker = GoogleWorkspaceSyncWorkerScript.new(db)
			_refresh_sync_status()

var sync_worker: RefCounted

@onready var status_pill: Label = $MarginContainer/MainVBox/SyncCard/SyncMargin/SyncVBox/StatusHBox/StatusPill
@onready var queue_pill: Label = $MarginContainer/MainVBox/SyncCard/SyncMargin/SyncVBox/StatusHBox/QueuePill
@onready var btn_sync_now: Button = $MarginContainer/MainVBox/SyncCard/SyncMargin/SyncVBox/StatusHBox/BtnSyncNow
@onready var credentials_card: PanelContainer = $MarginContainer/MainVBox/CredentialsCard
@onready var outbox_log_card: PanelContainer = $MarginContainer/MainVBox/OutboxLogCard

func _ready() -> void:
	_init_database()
	_style_cards()
	_populate_credentials_card()
	_connect_signals()
	_refresh_sync_status()

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
	if not sync_worker:
		sync_worker = GoogleWorkspaceSyncWorkerScript.new(db)

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
	if btn_sync_now: btn_sync_now.pressed.connect(_on_sync_now_pressed)

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
	form_vbox.add_child(e2)

	vbox.add_child(form_vbox)
	credentials_card.add_child(vbox)

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
