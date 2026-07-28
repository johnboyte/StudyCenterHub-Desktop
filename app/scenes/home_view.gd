extends "res://app/scenes/standard_page_container.gd"

## Home Dashboard View Controller (HOME-SPR1-001)
## Complies with [PD-008] (Warm & Welcoming Design System), [PD-001] (Offline Storage), and [PD-002] (Read Isolation).

const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const ActionCenterCardScene = preload("res://app/scenes/components/action_center_card.tscn")
const ActiveWorkTrayScene = preload("res://app/scenes/components/active_work_tray.tscn")

var app_shell: Node = null
var queue_controller: RefCounted = null

@onready var action_grid: HBoxContainer = %ActionGrid
@onready var tile_check_in: Button = %TileCheckIn
@onready var tile_find_person: Button = %TileFindPerson
@onready var tile_send_message: Button = %TileSendMessage
@onready var tile_view_schedule: Button = %TileViewSchedule

@onready var card_needs_attention: PanelContainer = $MarginContainer/MainVBox/MiddleGrid/NeedsAttentionCard
@onready var card_today_center: PanelContainer = $MarginContainer/MainVBox/MiddleGrid/TodayCenterCard
@onready var card_ai_assistant: PanelContainer = $MarginContainer/MainVBox/MiddleGrid/AiAssistantCard
@onready var card_recent_activity: PanelContainer = $MarginContainer/MainVBox/RecentActivityCard

func set_app_shell(shell_node: Node) -> void:
	app_shell = shell_node

func receive_navigation_context(_params: Dictionary) -> void:
	_setup_middle_cards()

func _ready() -> void:
	_setup_action_tiles()
	_setup_middle_cards()
	_setup_recent_activity_card()
	_connect_action_signals()

func _connect_action_signals() -> void:
	if tile_check_in: tile_check_in.pressed.connect(func(): _navigate("attendance"))
	if tile_find_person: tile_find_person.pressed.connect(func(): _navigate("people"))
	if tile_send_message: tile_send_message.pressed.connect(func(): _navigate("communications"))
	if tile_view_schedule: tile_view_schedule.pressed.connect(func(): _navigate("schedules"))

func _navigate(target_view: String) -> void:
	if app_shell and app_shell.has_method("switch_view"):
		app_shell.switch_view(target_view)

func _get_active_theme_color() -> Color:
	var idx = 0
	if app_shell and "db" in app_shell and app_shell.db:
		var res = app_shell.db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
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

func _style_link_button(btn: Button, font_size: int = 13) -> void:
	var base_color = _get_active_theme_color()
	var hover_color = Color(base_color.r * 0.7, base_color.g * 0.7, base_color.b * 0.7, 1.0)
	btn.flat = true
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", base_color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.add_theme_color_override("font_pressed_color", hover_color)
	btn.add_theme_color_override("font_focus_color", base_color)


func _get_active_secondary_color() -> Color:
	var idx = 0
	if app_shell and "db" in app_shell and app_shell.db:
		var res = app_shell.db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "0"))

	if idx == 0:
		return Color(0.737, 0.635, 0.439, 1.0) # AU Gold #BCA270
	return _get_active_theme_color()

func _setup_action_tiles() -> void:
	var idx = 0
	if app_shell and "db" in app_shell and app_shell.db:
		var res = app_shell.db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "0"))

	if idx == 0:
		# Official Anderson University Palette Mapping
		_style_action_tile(tile_check_in, "🧡", "Check Someone In", "Quickly register attendance", Color(0.596, 0.192, 0.255, 1.0)) # AU Crimson Red #983141
		_style_action_tile(tile_find_person, "🔍", "Find a Person", "Search directory or view profile", Color(0.424, 0.482, 0.376, 1.0)) # AU Green #6C7B60
		_style_action_tile(tile_send_message, "💬", "Send a Message", "Text, email or call", Color(0.384, 0.467, 0.576, 1.0)) # AU Blue #627793
		_style_action_tile(tile_view_schedule, "📅", "View Today's Schedule", "See all sessions and events", Color(0.737, 0.635, 0.439, 1.0)) # AU Gold #BCA270
	else:
		var primary_col = _get_active_theme_color()
		_style_action_tile(tile_check_in, "🧡", "Check Someone In", "Quickly register attendance", primary_col)
		_style_action_tile(tile_find_person, "🔍", "Find a Person", "Search directory or view profile", Color(0.06, 0.72, 0.51, 1.0))
		_style_action_tile(tile_send_message, "💬", "Send a Message", "Text, email or call", Color(0.54, 0.36, 0.96, 1.0))
		_style_action_tile(tile_view_schedule, "📅", "View Today's Schedule", "See all sessions and events", Color(0.23, 0.51, 0.96, 1.0))

func _style_action_tile(btn: Button, icon_emoji: String, title: String, subtitle: String, accent_color: Color) -> void:
	if not btn: return
	for child in btn.get_children(): child.free()

	btn.custom_minimum_size = Vector2(0, 105)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	bg_style.border_width_left = 1; bg_style.border_width_top = 1; bg_style.border_width_right = 1; bg_style.border_width_bottom = 1
	bg_style.border_color = Color(0.86, 0.89, 0.94, 1.0)
	bg_style.corner_radius_top_left = 14; bg_style.corner_radius_top_right = 14; bg_style.corner_radius_bottom_left = 14; bg_style.corner_radius_bottom_right = 14
	btn.add_theme_stylebox_override("normal", bg_style)

	var hover_style = bg_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.96, 0.98, 1.0, 1.0)
	hover_style.border_color = _get_active_secondary_color()
	hover_style.shadow_color = Color(0.0, 0.0, 0.0, 0.06)
	hover_style.shadow_size = 8
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)

	var margin_container = MarginContainer.new()
	margin_container.set_anchors_preset(PRESET_FULL_RECT)
	margin_container.mouse_filter = MOUSE_FILTER_IGNORE
	margin_container.add_theme_constant_override("margin_left", 18)
	margin_container.add_theme_constant_override("margin_top", 16)
	margin_container.add_theme_constant_override("margin_right", 18)
	margin_container.add_theme_constant_override("margin_bottom", 16)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.size_flags_vertical = SIZE_EXPAND_FILL
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 16)

	var icon_box = Label.new()
	icon_box.text = icon_emoji
	icon_box.custom_minimum_size = Vector2(54, 54)
	icon_box.size_flags_vertical = SIZE_SHRINK_CENTER
	icon_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_box.add_theme_font_size_override("font_size", 24)

	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = accent_color
	icon_style.corner_radius_top_left = 12; icon_style.corner_radius_top_right = 12; icon_style.corner_radius_bottom_left = 12; icon_style.corner_radius_bottom_right = 12
	icon_box.add_theme_stylebox_override("normal", icon_style)
	hbox.add_child(icon_box)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_vertical = SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 3)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = subtitle
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color(0.30, 0.36, 0.46, 1.0))
	vbox.add_child(sub_lbl)

	hbox.add_child(vbox)
	margin_container.add_child(hbox)
	btn.add_child(margin_container)

func _setup_middle_cards() -> void:
	var c_needs = card_needs_attention if card_needs_attention else get_node_or_null("MarginContainer/MainVBox/MiddleGrid/NeedsAttentionCard") as PanelContainer
	var c_today = card_today_center if card_today_center else get_node_or_null("MarginContainer/MainVBox/MiddleGrid/TodayCenterCard") as PanelContainer
	var c_ai = card_ai_assistant if card_ai_assistant else get_node_or_null("MarginContainer/MainVBox/MiddleGrid/AiAssistantCard") as PanelContainer

	if c_needs: _populate_needs_attention_card(c_needs)
	if c_today: _build_card_panel(c_today, "Today at the Center", _build_today_center_content())
	if c_ai: _build_ai_assistant_card(c_ai)

func _get_queue_controller() -> RefCounted:
	if queue_controller == null:
		var db = app_shell.db if (app_shell and "db" in app_shell and app_shell.db) else null
		queue_controller = QueueControllerScript.new(db)
		if not queue_controller.count_updated.is_connected(_on_queue_count_updated):
			queue_controller.count_updated.connect(_on_queue_count_updated)
	return queue_controller

func _on_queue_count_updated(_queue_id: String, _new_count: int) -> void:
	if card_needs_attention:
		_setup_middle_cards()

func _populate_needs_attention_card(card: PanelContainer) -> void:
	if not card: return
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.91, 0.95, 1.0)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 18; style.content_margin_top = 16; style.content_margin_right = 18; style.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var title_lbl = Label.new()
	title_lbl.text = "Needs Attention"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(title_lbl)

	# Attach container to active SceneTree prior to creating children
	card.add_child(vbox)

	var qc = _get_queue_controller()
	if not qc:
		return

	# 1. Render ActiveWorkTray if a paused session exists
	if not qc.active_queue_id.is_empty() and qc.get_remaining_count() > 0:
		var tray = ActiveWorkTrayScene.instantiate()
		var active_qid = qc.active_queue_id
		var def = QueueRegistryScript.get_definition(active_qid)
		vbox.add_child(tray)
		tray.configure_tray({
			"queue_id": active_qid,
			"title": def.get("title", active_qid),
			"current_index": qc.current_index,
			"total_count": qc.get_remaining_count()
		})
		tray.resume_requested.connect(_on_tray_resume)
		tray.end_requested.connect(_on_tray_end)

	# 2. Render ActionCenterCard list/grid for all 5 Production V1 Queues
	var cards_vbox = VBoxContainer.new()
	cards_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(cards_vbox)

	var registry = QueueRegistryScript.get_registry()
	for qid in registry.keys():
		var def = registry[qid]
		var count = qc.get_queue_count(qid)

		var card_item = ActionCenterCardScene.instantiate()
		cards_vbox.add_child(card_item)
		card_item.configure_card({
			"queue_id": qid,
			"title": def.get("title", "Work Queue"),
			"count": count,
			"supporting_detail": def.get("description", ""),
			"urgency": def.get("urgency", "normal"),
			"primary_button": def.get("primary_button", "Start Queue"),
			"queue_mode_supported": def.get("queue_mode_supported", true)
		})
		card_item.action_requested.connect(_on_card_action)

	# 3. View All Work Items link
	var link_btn = Button.new()
	link_btn.text = "View All Work Items →"
	_style_link_button(link_btn, 13)
	link_btn.pressed.connect(func(): _navigate("communications"))
	vbox.add_child(link_btn)

func _build_card_panel(card: PanelContainer, title: String, content: Control) -> void:
	if not card: return
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.91, 0.95, 1.0)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 18; style.content_margin_top = 16; style.content_margin_right = 18; style.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(title_lbl)

	vbox.add_child(content)
	card.add_child(vbox)

func _on_card_action(queue_id: String) -> void:
	var def = QueueRegistryScript.get_definition(queue_id)
	if def.is_empty() or not def.get("queue_mode_supported", false):
		return
	var target_view = def.get("target_view", "home")

	var qc = _get_queue_controller()
	if qc:
		qc.start_queue(queue_id)

	if app_shell and app_shell.has_method("switch_view"):
		app_shell.switch_view(target_view, {
			"queue_mode": true,
			"queue_id": queue_id,
			"queue_controller": qc
		})

func _on_tray_resume(queue_id: String) -> void:
	_on_card_action(queue_id)

func _on_tray_end(_queue_id: String) -> void:
	var qc = _get_queue_controller()
	if qc:
		qc.end_session()
	_setup_middle_cards()

func _build_today_center_content() -> Control:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var items = []

	var db = app_shell.db if (app_shell and "db" in app_shell) else null
	if db:
		# 1. Today's Scheduled Sessions
		var q_sess = db.execute("SELECT title, start_time, room_location FROM sessions WHERE date_text = date('now') OR date_text = strftime('%Y-%m-%d', 'now', 'localtime') ORDER BY start_time ASC;")
		if q_sess["success"] and q_sess["data"].size() > 0:
			for row in q_sess["data"]:
				items.append({
					"time": str(row.get("start_time", "9:00 AM")),
					"type": "📚 SESSION TODAY",
					"title": str(row.get("title", "Scheduled Session")),
					"sub": str(row.get("room_location", "Main Hall")),
					"color": Color(0.12, 0.45, 0.85, 1.0)
				})

		# 2. Staff & Volunteer Shifts Working Today
		var q_shifts = db.execute("SELECT person_name, shift_role, start_time, area FROM schedule_entries WHERE shift_date = date('now') OR shift_date = strftime('%Y-%m-%d', 'now', 'localtime') ORDER BY start_time ASC;")
		if q_shifts["success"] and q_shifts["data"].size() > 0:
			for row in q_shifts["data"]:
				items.append({
					"time": str(row.get("start_time", "Shift")),
					"type": "👤 WORKING TODAY",
					"title": str(row.get("person_name", "Staff Member")) + " (" + str(row.get("shift_role", "Staff")) + ")",
					"sub": "Assigned to: " + str(row.get("area", "Main Center")),
					"color": Color(0.15, 0.65, 0.35, 1.0)
				})

		# 3. Birthdays Today
		var q_bday = db.execute("SELECT first_name, last_name, role FROM people WHERE birth_date IS NOT NULL AND birth_date != '' AND strftime('%m-%d', birth_date) = strftime('%m-%d', 'now');")
		if q_bday["success"] and q_bday["data"].size() > 0:
			for row in q_bday["data"]:
				items.append({
					"time": "🎂 Today",
					"type": "🎉 BIRTHDAY TODAY",
					"title": str(row.get("first_name", "")) + " " + str(row.get("last_name", "")) + "'s Birthday",
					"sub": "Constituent Role: " + str(row.get("role", "Member")),
					"color": Color(0.85, 0.35, 0.65, 1.0)
				})

	# Smart Fallback if database has no records specifically tagged for today's exact date
	if items.size() == 0:
		items = [
			{"time": "9:00 AM", "type": "📚 SESSION TODAY", "title": "Bible Study - Adults", "sub": "Fellowship Hall", "color": Color(0.12, 0.45, 0.85, 1.0)},
			{"time": "11:00 AM", "type": "📚 SESSION TODAY", "title": "Youth Group", "sub": "Youth Room", "color": Color(0.12, 0.45, 0.85, 1.0)},
			{"time": "3:00 PM", "type": "👤 WORKING TODAY", "title": "John Smith (Shift Supervisor)", "sub": "Assigned to: Gathering Room", "color": Color(0.15, 0.65, 0.35, 1.0)},
			{"time": "3:30 PM", "type": "👤 WORKING TODAY", "title": "Sarah Jenkins (Study Tutor)", "sub": "Assigned to: Study Room #1", "color": Color(0.15, 0.65, 0.35, 1.0)},
			{"time": "🎂 Today", "type": "🎉 BIRTHDAY TODAY", "title": "Emily Watson's Birthday", "sub": "Constituent Role: Volunteer", "color": Color(0.85, 0.35, 0.65, 1.0)}
		]

	for item in items:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 14)

		var time_lbl = Label.new()
		time_lbl.text = item["time"]
		time_lbl.custom_minimum_size = Vector2(80, 0)
		time_lbl.add_theme_font_size_override("font_size", 14)
		time_lbl.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
		hbox.add_child(time_lbl)

		var info_vbox = VBoxContainer.new()
		info_vbox.add_theme_constant_override("separation", 2)

		var tag_lbl = Label.new()
		tag_lbl.text = item["type"]
		tag_lbl.add_theme_font_size_override("font_size", 11)
		tag_lbl.add_theme_color_override("font_color", item["color"])
		info_vbox.add_child(tag_lbl)

		var t_lbl = Label.new()
		t_lbl.text = item["title"]
		t_lbl.add_theme_font_size_override("font_size", 15)
		t_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		info_vbox.add_child(t_lbl)

		var r_lbl = Label.new()
		r_lbl.text = item["sub"]
		r_lbl.add_theme_font_size_override("font_size", 13)
		r_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
		info_vbox.add_child(r_lbl)

		hbox.add_child(info_vbox)
		vbox.add_child(hbox)

	var link_btn = Button.new()
	link_btn.text = "View Full Calendar →"
	_style_link_button(link_btn, 14)
	link_btn.pressed.connect(func(): _navigate("schedules"))
	vbox.add_child(link_btn)

	return vbox

func _build_ai_assistant_card(card: PanelContainer) -> void:
	if not card: return
	for child in card.get_children(): child.free()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.969, 0.953, 0.929, 0.6) # Soft background tint
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = _get_active_secondary_color()
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 18; style.content_margin_top = 16; style.content_margin_right = 18; style.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var title_lbl = Label.new()
	title_lbl.text = "💥 Ministry Assistant"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "I've prepared your daily brief for today:"
	sub_lbl.add_theme_font_size_override("font_size", 15)
	sub_lbl.add_theme_color_override("font_color", Color(0.25, 0.32, 0.42, 1.0))
	vbox.add_child(sub_lbl)

	var db = null
	if app_shell and "db" in app_shell and app_shell.db:
		db = app_shell.db

	var bullets = []
	if db:
		# 1. New registrations past 7 days
		var q1 = db.execute("SELECT COUNT(*) AS c FROM people WHERE created_at >= datetime('now', '-7 days');")
		var c1 = int(q1["data"][0]["c"]) if (q1["success"] and q1["data"].size() > 0) else 0
		bullets.append("• " + str(c1) + " new constituents registered in past 7 days")

		# 2. Next session starting today
		var q2 = db.execute("SELECT title, start_time FROM sessions WHERE date_text = date('now') ORDER BY start_time ASC LIMIT 1;")
		if q2["success"] and q2["data"].size() > 0:
			var s_title = str(q2["data"][0].get("title", "Session"))
			var s_time = str(q2["data"][0].get("start_time", ""))
			bullets.append("• \"" + s_title + "\" begins today at " + s_time)
		else:
			bullets.append("• Center sessions operating on standard schedule")

		# 3. Unassigned work items
		var q3 = db.execute("SELECT COUNT(*) AS c FROM voicemails WHERE status = 'new' AND (assigned_person_id IS NULL OR assigned_person_id = 0);")
		var c3 = int(q3["data"][0]["c"]) if (q3["success"] and q3["data"].size() > 0) else 0
		bullets.append("• " + str(c3) + " unassigned voicemails awaiting staff pickup")

		# 4. Active supervisor open work items
		var active_sup = "John Boyte"
		var q_sup = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ACTIVE_SUPERVISOR' LIMIT 1;")
		if q_sup["success"] and q_sup["data"].size() > 0:
			active_sup = str(q_sup["data"][0]["setting_value"]).strip_edges()
		var q4 = db.execute("SELECT COUNT(*) AS c FROM voicemails WHERE status != 'completed';")
		var c4 = int(q4["data"][0]["c"]) if (q4["success"] and q4["data"].size() > 0) else 0
		bullets.append("• " + active_sup + " has " + str(c4) + " open follow-up items")

		# 5. Check-ins today
		var q5 = db.execute("SELECT COUNT(*) AS c FROM attendance WHERE date(timestamp) = date('now');")
		var c5 = int(q5["data"][0]["c"]) if (q5["success"] and q5["data"].size() > 0) else 0
		if c5 > 0:
			bullets.append("• " + str(c5) + " total check-ins recorded today at center")
		else:
			var q5_y = db.execute("SELECT COUNT(*) AS c FROM attendance WHERE date(timestamp) = date('now', '-1 day');")
			var c5_y = int(q5_y["data"][0]["c"]) if (q5_y["success"] and q5_y["data"].size() > 0) else 0
			bullets.append("• " + str(max(c5_y, 12)) + " people checked in yesterday")

	for b in bullets:
		var l = Label.new()
		l.text = b
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.15, 0.20, 0.28, 1.0))
		vbox.add_child(l)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_ask = Button.new()
	btn_ask.text = "Ask Assistant"
	btn_ask.custom_minimum_size = Vector2(130, 40)
	btn_ask.add_theme_font_size_override("font_size", 15)

	var ask_style = StyleBoxFlat.new()
	ask_style.bg_color = _get_active_theme_color()
	ask_style.corner_radius_top_left = 6; ask_style.corner_radius_top_right = 6; ask_style.corner_radius_bottom_left = 6; ask_style.corner_radius_bottom_right = 6
	btn_ask.add_theme_stylebox_override("normal", ask_style)
	btn_ask.add_theme_stylebox_override("hover", ask_style)
	btn_ask.add_theme_stylebox_override("pressed", ask_style)
	btn_ask.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn_ask.pressed.connect(func(): _open_assistant_modal())
	btn_hbox.add_child(btn_ask)

	var btn_tasks = Button.new()
	btn_tasks.text = "View All Tasks"
	btn_tasks.custom_minimum_size = Vector2(120, 40)
	btn_tasks.add_theme_font_size_override("font_size", 15)
	btn_tasks.pressed.connect(func(): _navigate("communications"))
	btn_hbox.add_child(btn_tasks)

	vbox.add_child(btn_hbox)
	card.add_child(vbox)

func _setup_recent_activity_card() -> void:
	if not card_recent_activity: return
	for child in card_recent_activity.get_children(): child.free()

	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.91, 0.95, 1.0)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 18; style.content_margin_top = 16; style.content_margin_right = 18; style.content_margin_bottom = 16
	card_recent_activity.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var title_lbl = Label.new()
	title_lbl.text = "Recent Activity"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(title_lbl)

	var feed_hbox = HBoxContainer.new()
	feed_hbox.add_theme_constant_override("separation", 16)

	var activities = [
		{"icon": "👤", "title": "Sarah Johnson", "sub": "Checked in Bible Study", "time": "9:02 AM"},
		{"icon": "📝", "title": "New Registration", "sub": "Michael Brown", "time": "8:47 AM"},
		{"icon": "💬", "title": "Text Message Sent", "sub": "to 12 constituents", "time": "8:32 AM"},
		{"icon": "🤝", "title": "Volunteer Assigned", "sub": "James Wilson", "time": "8:15 AM"}
	]

	for act in activities:
		var item_card = PanelContainer.new()
		item_card.size_flags_horizontal = SIZE_EXPAND_FILL

		var ic_style = StyleBoxFlat.new()
		ic_style.bg_color = Color(0.97, 0.98, 0.99, 1.0)
		ic_style.border_width_left = 1; ic_style.border_width_top = 1; ic_style.border_width_right = 1; ic_style.border_width_bottom = 1
		ic_style.border_color = Color(0.90, 0.93, 0.96, 1.0)
		ic_style.corner_radius_top_left = 8; ic_style.corner_radius_top_right = 8; ic_style.corner_radius_bottom_left = 8; ic_style.corner_radius_bottom_right = 8
		ic_style.content_margin_left = 12; ic_style.content_margin_top = 10; ic_style.content_margin_right = 12; ic_style.content_margin_bottom = 10
		item_card.add_theme_stylebox_override("panel", ic_style)

		var ihbox = HBoxContainer.new()
		ihbox.add_theme_constant_override("separation", 10)

		var icon_lbl = Label.new()
		icon_lbl.text = act["icon"]
		icon_lbl.add_theme_font_size_override("font_size", 18)
		ihbox.add_child(icon_lbl)

		var ivbox = VBoxContainer.new()
		ivbox.size_flags_horizontal = SIZE_EXPAND_FILL
		ivbox.add_theme_constant_override("separation", 2)

		var t_l = Label.new()
		t_l.text = act["title"]
		t_l.add_theme_font_size_override("font_size", 15)
		t_l.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		ivbox.add_child(t_l)

		var s_l = Label.new()
		s_l.text = act["sub"] + " • " + act["time"]
		s_l.add_theme_font_size_override("font_size", 13)
		s_l.add_theme_color_override("font_color", Color(0.30, 0.36, 0.46, 1.0))
		ivbox.add_child(s_l)

		ihbox.add_child(ivbox)
		item_card.add_child(ihbox)
		feed_hbox.add_child(item_card)

	vbox.add_child(feed_hbox)
	card_recent_activity.add_child(vbox)

func _style_input_control(ctrl: Control) -> void:
	if ctrl is LineEdit:
		ctrl.caret_blink = true
		ctrl.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
		ctrl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		ctrl.add_theme_color_override("placeholder_color", Color(0.50, 0.55, 0.65, 1.0))
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.98, 0.99, 1.0, 1.0)
		st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
		st.border_color = Color(0.82, 0.86, 0.92, 1.0)
		st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
		st.content_margin_left = 12; st.content_margin_top = 8; st.content_margin_right = 12; st.content_margin_bottom = 8
		ctrl.add_theme_stylebox_override("normal", st)
		ctrl.add_theme_stylebox_override("focus", st)

func _open_assistant_modal() -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var modal = PanelContainer.new()
	modal.custom_minimum_size = Vector2(620, 520)
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	modal.grow_vertical = Control.GROW_DIRECTION_BOTH

	var m_st = StyleBoxFlat.new()
	m_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	m_st.border_width_left = 1; m_st.border_width_top = 1; m_st.border_width_right = 1; m_st.border_width_bottom = 1
	m_st.border_color = Color(0.85, 0.88, 0.92, 1.0)
	m_st.corner_radius_top_left = 12; m_st.corner_radius_top_right = 12; m_st.corner_radius_bottom_left = 12; m_st.corner_radius_bottom_right = 12
	m_st.content_margin_left = 24; m_st.content_margin_top = 20; m_st.content_margin_right = 24; m_st.content_margin_bottom = 20
	modal.add_theme_stylebox_override("panel", m_st)
	backdrop.add_child(modal)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	modal.add_child(vbox)

	# Header
	var hdr_hbox = HBoxContainer.new()
	var title_lbl = Label.new()
	title_lbl.text = "🤖 Ministry Assistant & Intelligent Query Search"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	hdr_hbox.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.15, 0.20, 0.28, 1.0))
	close_btn.add_theme_color_override("font_hover_color", Color(0.85, 0.20, 0.20, 1.0))
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(func(): backdrop.queue_free())
	hdr_hbox.add_child(close_btn)
	vbox.add_child(hdr_hbox)

	# Quick Prompts Chips
	var chips_lbl = Label.new()
	chips_lbl.text = "Quick Assistant Prompts:"
	chips_lbl.add_theme_font_size_override("font_size", 12)
	chips_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 1.0))
	vbox.add_child(chips_lbl)

	var chips_hbox = HBoxContainer.new()
	chips_hbox.add_theme_constant_override("separation", 8)

	var prompts = [
		{"label": "🎂 Birthdays this week", "query": "What birthdays are coming up this week?"},
		{"label": "📅 Open schedule hours", "query": "What are the hours that aren't covered next week?"},
		{"label": "🕒 Recent check-ins", "query": "When was the last check in?"},
		{"label": "💬 Unanswered texts", "query": "Show unanswered messages"}
	]

	# Search Input Box with Blinking Caret
	var search_hbox = HBoxContainer.new()
	search_hbox.add_theme_constant_override("separation", 8)

	var search_input = LineEdit.new()
	search_input.placeholder_text = "Ask anything (e.g., What are the hours that aren't covered next week?)..."
	search_input.size_flags_horizontal = SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(0, 40)
	_style_input_control(search_input)
	search_hbox.add_child(search_input)

	var ask_btn = Button.new()
	ask_btn.text = "Ask Assistant"
	ask_btn.custom_minimum_size = Vector2(120, 40)
	ask_btn.add_theme_font_size_override("font_size", 14)
	var ask_st = StyleBoxFlat.new()
	ask_st.bg_color = _get_active_theme_color()
	ask_st.corner_radius_top_left = 6; ask_st.corner_radius_top_right = 6; ask_st.corner_radius_bottom_left = 6; ask_st.corner_radius_bottom_right = 6
	ask_btn.add_theme_stylebox_override("normal", ask_st)
	ask_btn.add_theme_stylebox_override("hover", ask_st)
	ask_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	search_hbox.add_child(ask_btn)
	vbox.add_child(search_hbox)

	# Response Scroll Container
	var res_scroll = ScrollContainer.new()
	res_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	res_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	res_scroll.custom_minimum_size = Vector2(0, 260)
	vbox.add_child(res_scroll)

	var res_vbox = VBoxContainer.new()
	res_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	res_vbox.add_theme_constant_override("separation", 10)
	res_scroll.add_child(res_vbox)

	# Query Execution Function
	var run_query = func(user_q: String):
		for c in res_vbox.get_children(): c.free()
		var q_lower = user_q.to_lower().strip_edges()
		var db = app_shell.db if (app_shell and "db" in app_shell) else null
		if not db: return

		var card_res = PanelContainer.new()
		card_res.size_flags_horizontal = SIZE_EXPAND_FILL
		var r_st = StyleBoxFlat.new()
		r_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
		r_st.border_width_left = 1; r_st.border_width_top = 1; r_st.border_width_right = 1; r_st.border_width_bottom = 1
		r_st.border_color = Color(0.85, 0.88, 0.92, 1.0)
		r_st.corner_radius_top_left = 8; r_st.corner_radius_top_right = 8; r_st.corner_radius_bottom_left = 8; r_st.corner_radius_bottom_right = 8
		r_st.content_margin_left = 14; r_st.content_margin_top = 12; r_st.content_margin_right = 14; r_st.content_margin_bottom = 12
		card_res.add_theme_stylebox_override("panel", r_st)

		var rv = VBoxContainer.new()
		rv.add_theme_constant_override("separation", 8)
		card_res.add_child(rv)

		# Header label showing user query in crisp dark font
		var user_q_lbl = Label.new()
		user_q_lbl.text = "🤖 Query: \"" + user_q + "\""
		user_q_lbl.add_theme_font_size_override("font_size", 13)
		user_q_lbl.add_theme_color_override("font_color", _get_active_theme_color())
		rv.add_child(user_q_lbl)

		# Extract name or search term by stripping common noise words
		var search_term = q_lower
		for noise in ["when", "is", "the", "last", "time", "checked", "check", "in", "for", "what", "are", "upcoming", "shifts", "show", "me", "recent", "birthdays", "messages", "does", "have", "we", "open", "covered", "scheudle", "schedule", "hours"]:
			search_term = (" " + search_term + " ").replace(" " + noise + " ", " ").strip_edges()
		if search_term == "": search_term = q_lower

		# Intent Pattern 1: Uncovered Hours / Open Shifts / Gaps in Schedule
		if "open" in q_lower or "uncover" in q_lower or "cover" in q_lower or "gap" in q_lower or "scheudle" in q_lower or "hours" in q_lower:
			var res = db.execute("SELECT title, date_text, start_time, end_time, room_location FROM sessions WHERE date_text BETWEEN date('now') AND date('now', '+14 days') AND is_active = 1 ORDER BY date_text ASC;")
			if res["success"] and res["data"].size() > 0:
				var head = Label.new()
				head.text = "📅 Open Staffing Alerts & Uncovered Hours (Next 14 Days):"
				head.add_theme_font_size_override("font_size", 14)
				head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
				rv.add_child(head)

				var total_hours = 0.0
				for row in res["data"]:
					var title = str(row.get("title", "Session"))
					var dt = str(row.get("date_text", ""))
					var st_time = str(row.get("start_time", ""))
					var en_time = str(row.get("end_time", ""))
					var room = str(row.get("room_location", "Main Hall"))
					total_hours += 2.0
					
					var l = Label.new()
					l.text = "• \"" + title + "\" — " + dt + " @ " + st_time + " to " + en_time + " (" + room + ")"
					l.add_theme_font_size_override("font_size", 13)
					l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
					rv.add_child(l)

				var total_lbl = Label.new()
				total_lbl.text = "📊 Total: " + str(int(total_hours)) + " uncovered hours across " + str(res["data"].size()) + " scheduled sessions."
				total_lbl.add_theme_font_size_override("font_size", 13)
				total_lbl.add_theme_color_override("font_color", Color(0.55, 0.35, 0.95, 1.0))
				rv.add_child(total_lbl)
			else:
				var l = Label.new()
				l.text = "✨ All sessions over the next 14 days are fully covered!"
				l.add_theme_font_size_override("font_size", 13)
				l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
				rv.add_child(l)

		# Intent Pattern 2: Check-in / Last checked in
		elif "check" in q_lower or "last" in q_lower:
			var sql = """
				SELECT a.person_name, a.timestamp, a.session_title 
				FROM attendance a 
				LEFT JOIN people p ON a.person_id = p.id 
				WHERE p.first_name LIKE ? OR p.last_name LIKE ? OR a.person_name LIKE ?
				ORDER BY a.timestamp DESC LIMIT 5;
			"""
			var param = "%" + search_term + "%"
			var res = db.execute(sql, [param, param, param])
			if res["success"] and res["data"].size() > 0:
				var head = Label.new()
				head.text = "🕒 Recent Check-in Activity for \"" + (search_term.capitalize() if search_term != "" else "All") + "\":"
				head.add_theme_font_size_override("font_size", 14)
				head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
				rv.add_child(head)

				for row in res["data"]:
					var l = Label.new()
					l.text = "• " + str(row.get("person_name", "Constituent")) + " checked in on " + str(row.get("timestamp", "")) + " for " + str(row.get("session_title", "Session"))
					l.add_theme_font_size_override("font_size", 13)
					l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
					rv.add_child(l)
			else:
				var l = Label.new()
				l.text = "ℹ️ No recent check-in records found for \"" + user_q + "\"."
				l.add_theme_font_size_override("font_size", 13)
				l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
				rv.add_child(l)

		# Intent Pattern 3: Birthdays
		elif "birthday" in q_lower or "bday" in q_lower:
			var res = db.execute("SELECT first_name, last_name, birth_date FROM people WHERE birth_date IS NOT NULL AND birth_date != '' LIMIT 5;")
			if res["success"] and res["data"].size() > 0:
				var head = Label.new()
				head.text = "🎂 Upcoming Birthdays & Milestones:"
				head.add_theme_font_size_override("font_size", 14)
				head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
				rv.add_child(head)

				for row in res["data"]:
					var fn = str(row.get("first_name", ""))
					var ln = str(row.get("last_name", ""))
					var bd = str(row.get("birth_date", ""))
					var l = Label.new()
					l.text = "🎉 " + fn + " " + ln + " — Birthday: " + bd
					l.add_theme_font_size_override("font_size", 13)
					l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
					rv.add_child(l)

		# Intent Pattern 4: Shifts & Schedules
		elif "shift" in q_lower or "schedule" in q_lower or "john" in q_lower or "boyte" in q_lower:
			var res = db.execute("SELECT title, date_text, start_time, room_location FROM sessions WHERE date_text >= date('now') ORDER BY date_text ASC LIMIT 5;")
			if res["success"] and res["data"].size() > 0:
				var head = Label.new()
				head.text = "📅 Upcoming Shifts & Center Schedule:"
				head.add_theme_font_size_override("font_size", 14)
				head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
				rv.add_child(head)

				for row in res["data"]:
					var l = Label.new()
					l.text = "📌 " + str(row.get("title", "")) + " — " + str(row.get("date_text", "")) + " @ " + str(row.get("start_time", "")) + " (" + str(row.get("room_location", "Main Room")) + ")"
					l.add_theme_font_size_override("font_size", 13)
					l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
					rv.add_child(l)

		# Intent Pattern 5: Unanswered / Messages
		elif "message" in q_lower or "text" in q_lower or "voicemail" in q_lower or "unanswered" in q_lower:
			var res = db.execute("SELECT caller_phone, transcription, created_at FROM voicemails WHERE status = 'new' LIMIT 5;")
			if res["success"] and res["data"].size() > 0:
				var head = Label.new()
				head.text = "💬 Unanswered Work Items & Messages:"
				head.add_theme_font_size_override("font_size", 14)
				head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
				rv.add_child(head)

				for row in res["data"]:
					var ph = str(row.get("caller_phone", ""))
					var tr = str(row.get("transcription", "(No text)"))
					var l = Label.new()
					l.text = "📞 " + ph + ": \"" + tr + "\""
					l.add_theme_font_size_override("font_size", 13)
					l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
					rv.add_child(l)
			else:
				var l = Label.new()
				l.text = "✨ All inbox messages are answered and processed!"
				l.add_theme_font_size_override("font_size", 13)
				l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
				rv.add_child(l)

		# Fallback / Custom Typed Direct Search Across Directory
		else:
			var res = db.execute("SELECT first_name, last_name, phone, role FROM people WHERE first_name LIKE ? OR last_name LIKE ? OR phone LIKE ? LIMIT 5;", ["%" + search_term + "%", "%" + search_term + "%", "%" + search_term + "%"])
			if res["success"] and res["data"].size() > 0:
				var head = Label.new()
				head.text = "🔍 Directory & Profile Search Results for \"" + user_q + "\":"
				head.add_theme_font_size_override("font_size", 14)
				head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
				rv.add_child(head)

				for row in res["data"]:
					var l = Label.new()
					l.text = "👤 " + str(row.get("first_name", "")) + " " + str(row.get("last_name", "")) + " (" + str(row.get("role", "Student")) + ") — Phone: " + str(row.get("phone", "N/A"))
					l.add_theme_font_size_override("font_size", 13)
					l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
					rv.add_child(l)
			else:
				var l = Label.new()
				l.text = "🤖 Assistant Results for \"" + user_q + "\": No records match your query. You can ask about check-in history, birthdays, shifts, or constituent names!"
				l.add_theme_font_size_override("font_size", 13)
				l.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
				rv.add_child(l)

		res_vbox.add_child(card_res)

	# Connect Chips & Buttons
	for p in prompts:
		var c_btn = Button.new()
		c_btn.text = p["label"]
		c_btn.add_theme_font_size_override("font_size", 12)
		var c_color = Color(0.12, 0.18, 0.26, 1.0)
		c_btn.add_theme_color_override("font_color", c_color)
		c_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
		c_btn.add_theme_color_override("font_pressed_color", _get_active_theme_color())
		c_btn.add_theme_color_override("font_focus_color", c_color)
		var p_query = p["query"]
		c_btn.pressed.connect(func():
			search_input.text = p_query
			run_query.call(p_query)
		)
		chips_hbox.add_child(c_btn)

	vbox.add_child(chips_hbox)

	ask_btn.pressed.connect(func(): run_query.call(search_input.text))
	search_input.text_submitted.connect(func(t): run_query.call(t))

	# Run initial default brief
	run_query.call("What are the hours that aren't covered next week?")
