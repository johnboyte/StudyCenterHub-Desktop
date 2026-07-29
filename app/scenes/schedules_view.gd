extends "res://app/scenes/standard_page_container.gd"

## Production Staffing Schedule Controller (SCH-SPR1-001+)
## Enhanced Normal Hour Selector & Reordering with Visual Auto-Save & Formatting.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const WorkQueueHeaderBarScene = preload("res://app/scenes/components/work_queue_header_bar.tscn")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const SessionStaffAssignmentDialogScript = preload("res://app/scenes/components/session_staff_assignment_dialog.gd")

var db: RefCounted:
	set(value):
		db = value
		if db:
			sch_service = SchedulesServiceScript.new(db)
			config_service = SessionConfigServiceScript.new(db)
			if is_node_ready():
				call_deferred("_refresh_tab_content")

var sch_service: RefCounted
var config_service: RefCounted
var active_top_tab: String = "shifts"
var active_shift_view_mode: String = "board" # "board" (Week Board View) or "table" (Table View)
var active_session_horizon: String = "upcoming"
var selected_filter_type_ids: Array = []

var selected_shift_ids: Dictionary = {} # Set of unique entry_uuid strings -> true
var selection_anchor_id: String = ""
var clipboard: Dictionary = {} # {"mode": "copy"|"cut", "source_shift_ids": Array, "shifts": Array, "anchor_day_index": int}
var paste_target_day_index: int = -1
var selected_session_id: int = 1
var is_hours_selector_visible: bool = false
var current_week_base_unix: int = 0

# Queue Mode Members
var is_queue_mode: bool = false
var active_queue_id: String = ""
var queue_controller: RefCounted = null
var header_bar_instance: Control = null
var queue_card_container: PanelContainer = null

# Front-End Editable Lists for Center Areas & Shift Roles
var available_areas: Array = ["Study Center", "Gathering Room", "Kitchen", "Study Room #1", "Study Room #2", "Study Room #3", "The Study", "The Back Porch", "Whole Center"]
var available_roles: Array = ["Volunteer", "Intern", "Staff", "Team Leader"]

# Standardized Time Selector Options (Used throughout the app!)
const STANDARD_TIME_SLOTS = [
	"06:00 AM", "06:30 AM", "07:00 AM", "07:30 AM",
	"08:00 AM", "08:30 AM", "09:00 AM", "09:30 AM",
	"10:00 AM", "10:30 AM", "11:00 AM", "11:30 AM",
	"12:00 PM", "12:30 PM", "01:00 PM", "01:30 PM",
	"02:00 PM", "02:30 PM", "03:00 PM", "03:30 PM",
	"04:00 PM", "04:30 PM", "05:00 PM", "05:30 PM",
	"06:00 PM", "06:30 PM", "07:00 PM", "07:30 PM",
	"08:00 PM", "08:30 PM", "09:00 PM", "09:30 PM"
]

# Dual Gesture Engine States
enum GestureMode { GESTURE_NONE, GESTURE_MARQUEE_SELECT, GESTURE_CARD_DRAG }
var current_gesture_mode: GestureMode = GestureMode.GESTURE_NONE

var drag_start_global: Vector2 = Vector2.ZERO
var press_start_msec: int = 0
var drag_source_shift_uuids: Array = []
var initial_click_shift_uuid: String = ""

var drag_preview_label: Label
var marquee_rect_control: ColorRect
var drop_indicator_line: ColorRect
var all_card_nodes: Array = []
var all_day_columns: Array = []

@onready var btn_tab_shifts: Button = %BtnTabShifts
@onready var btn_tab_sessions: Button = %BtnTabSessions
@onready var btn_tab_hours: Button = %BtnTabHours
@onready var content_card: PanelContainer = %ContentCard

const DAYS_META = [
	{"code": "Sun", "day_idx": 0, "name": "Sunday"},
	{"code": "Mon", "day_idx": 1, "name": "Monday"},
	{"code": "Tue", "day_idx": 2, "name": "Tuesday"},
	{"code": "Wed", "day_idx": 3, "name": "Wednesday"},
	{"code": "Thu", "day_idx": 4, "name": "Thursday"},
	{"code": "Fri", "day_idx": 5, "name": "Friday"},
	{"code": "Sat", "day_idx": 6, "name": "Saturday"}
]

func _ready() -> void:
	_init_database()
	_style_card()
	_connect_tab_buttons()
	_setup_marquee_and_preview_overlay()
	switch_top_tab("shifts")

func receive_navigation_context(params: Dictionary) -> void:
	if params.get("queue_mode", false) == true:
		var qid = params.get("queue_id", "")
		if qid == "uncovered_sessions" or qid == "uncovered_center_hours":
			configure_queue_mode(params)
		else:
			_clear_queue_mode()
	else:
		_clear_queue_mode()

func configure_queue_mode(params: Dictionary = {}) -> void:
	is_queue_mode = true
	active_queue_id = params.get("queue_id", "uncovered_sessions")

	if params.has("queue_controller") and params["queue_controller"] != null:
		queue_controller = params["queue_controller"]
	else:
		queue_controller = QueueControllerScript.new(db)

	if queue_controller:
		if db: queue_controller.db = db
		if queue_controller.active_queue_id != active_queue_id or queue_controller.active_items.size() == 0:
			queue_controller.start_queue(active_queue_id)

	_attach_header_bar()
	_refresh_queue_view()

func _get_main_vbox() -> VBoxContainer:
	if has_node("MarginContainer/MainVBox"):
		return $MarginContainer/MainVBox as VBoxContainer
	elif has_node("MarginContainer/VBoxContainer"):
		return $MarginContainer/VBoxContainer as VBoxContainer
	return null

func _get_std_hdr() -> Control:
	var vbox = _get_main_vbox()
	if vbox:
		if vbox.has_node("HeaderVBox"):
			return vbox.get_node("HeaderVBox") as Control
		elif vbox.has_node("HeaderBar"):
			return vbox.get_node("HeaderBar") as Control
		elif vbox.has_node("HeaderContainer"):
			return vbox.get_node("HeaderContainer") as Control
	return null

func _attach_header_bar() -> void:
	if header_bar_instance: return

	var parent_container = _get_main_vbox()
	if not parent_container:
		parent_container = get_child(0) if get_child_count() > 0 else self

	if parent_container:
		header_bar_instance = WorkQueueHeaderBarScene.instantiate()
		parent_container.add_child(header_bar_instance)
		if parent_container.has_method("move_child"):
			parent_container.move_child(header_bar_instance, 0)

		# Hide standard page header during active Queue Mode to eliminate header overlap
		var std_hdr = _get_std_hdr()
		if std_hdr:
			std_hdr.visible = false

		var cur_idx = queue_controller.current_index if queue_controller else 0
		var rem_count = queue_controller.get_remaining_count() if queue_controller else 0
		var def = QueueRegistryScript.get_definition(active_queue_id)
		var q_title = def.get("title", "Uncovered Sessions (Next 14d)")
		header_bar_instance.configure_header(q_title, cur_idx, rem_count)
		header_bar_instance.pause_requested.connect(_on_queue_pause)
		header_bar_instance.exit_requested.connect(_on_queue_exit)

func _clear_queue_mode() -> void:
	is_queue_mode = false
	active_queue_id = ""
	if header_bar_instance:
		header_bar_instance.queue_free()
		header_bar_instance = null
	if queue_card_container:
		queue_card_container.queue_free()
		queue_card_container = null

	# Restore standard page header upon exiting Queue Mode
	var std_hdr = _get_std_hdr()
	if std_hdr:
		std_hdr.visible = true

func _on_queue_pause() -> void:
	if header_bar_instance and queue_controller:
		header_bar_instance.update_progress(queue_controller.current_index, queue_controller.get_remaining_count())

func _on_queue_exit() -> void:
	if queue_controller:
		queue_controller.end_session()
	_clear_queue_mode()

func _refresh_queue_view() -> void:
	if not is_queue_mode: return

	var def = QueueRegistryScript.get_definition(active_queue_id)
	var q_title = def.get("title", "Work Queue")
	var cur_idx = queue_controller.current_index if queue_controller else 0
	var rem_count = queue_controller.get_remaining_count() if queue_controller else 0

	if header_bar_instance:
		header_bar_instance.update_progress(cur_idx, rem_count)

	if not queue_card_container:
		queue_card_container = PanelContainer.new()
		var parent_container = _get_main_vbox()
		if not parent_container:
			parent_container = get_child(0) if get_child_count() > 0 else self
		if parent_container:
			parent_container.add_child(queue_card_container)
			if parent_container.has_method("move_child") and header_bar_instance:
				parent_container.move_child(queue_card_container, 1)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.99, 1.0, 1.0)
	style.border_width_left = 2; style.border_width_top = 2; style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.35, 0.95, 1.0) # Purple accent for scheduling queue
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 20; style.content_margin_top = 18; style.content_margin_right = 20; style.content_margin_bottom = 18
	queue_card_container.add_theme_stylebox_override("panel", style)

	for child in queue_card_container.get_children():
		queue_card_container.remove_child(child)
		child.queue_free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	queue_card_container.add_child(vbox)

	if rem_count == 0 or not queue_controller:
		var empty_lbl = Label.new()
		empty_lbl.text = "✨ Queue Complete! All items in " + q_title + " have been resolved."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.18, 0.55, 0.35, 1.0))
		vbox.add_child(empty_lbl)

		var exit_btn = Button.new()
		exit_btn.text = "Return to Standard Schedules"
		exit_btn.custom_minimum_size = Vector2(240, 36)
		exit_btn.pressed.connect(_on_queue_exit)
		vbox.add_child(exit_btn)
		return

	var current_item = queue_controller.get_current_item()
	if current_item.is_empty():
		return

	var is_center_hours_queue = (active_queue_id == "uncovered_center_hours")
	var title_txt = str(current_item.get("title", current_item.get("day_name", "Study Center Operating Hours")))
	var date_txt = str(current_item.get("date_text", ""))
	var start_t = str(current_item.get("start_time", current_item.get("open_time", "")))
	var end_t = str(current_item.get("end_time", current_item.get("close_time", "")))
	var location_txt = str(current_item.get("room_location", "Main Study Center"))

	var hdr_lbl = Label.new()
	if is_center_hours_queue:
		hdr_lbl.text = "UNCOVERED CENTER HOURS — " + str(current_item.get("day_name", "")) + " (" + date_txt + ")"
	else:
		hdr_lbl.text = "UNCOVERED SESSION — " + title_txt
	hdr_lbl.add_theme_font_size_override("font_size", 16)
	hdr_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(hdr_lbl)

	var details_lbl = Label.new()
	details_lbl.text = "📅 Date: " + date_txt + " | ⏰ Hours: " + start_t + " - " + end_t + " | 📍 Location: " + location_txt
	details_lbl.add_theme_font_size_override("font_size", 14)
	details_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0))
	vbox.add_child(details_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_hbox)

	var comp_btn = Button.new()
	comp_btn.text = "✅ Assign Shift Coverage"
	comp_btn.custom_minimum_size = Vector2(220, 38)
	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = Color(0.85, 0.47, 0.02, 1.0) if is_center_hours_queue else Color(0.55, 0.35, 0.95, 1.0)
	btn_st.corner_radius_top_left = 6; btn_st.corner_radius_top_right = 6; btn_st.corner_radius_bottom_left = 6; btn_st.corner_radius_bottom_right = 6
	comp_btn.add_theme_stylebox_override("normal", btn_st)
	comp_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	comp_btn.pressed.connect(func(): _open_staff_assignment_dialog(current_item))
	btn_hbox.add_child(comp_btn)

func _open_staff_assignment_dialog(current_item: Dictionary) -> void:
	var item_to_config = current_item.duplicate(true)
	if not item_to_config.has("start_time") and item_to_config.has("open_time"):
		item_to_config["start_time"] = item_to_config["open_time"]
	if not item_to_config.has("end_time") and item_to_config.has("close_time"):
		item_to_config["end_time"] = item_to_config["close_time"]
	if not item_to_config.has("room_location"):
		item_to_config["room_location"] = "Gathering Room"

	var dlg = SessionStaffAssignmentDialogScript.new(db)
	dlg.configure_session(item_to_config)
	add_child(dlg)
	dlg.popup_centered()
	dlg.staff_assigned.connect(func(payload: Dictionary):
		if sch_service:
			sch_service.create_shift_entry_atomic(
				payload["person_name"],
				payload["shift_role"],
				payload["shift_date"],
				payload["start_time"],
				payload["end_time"],
				payload["area"],
				payload["notes"]
			)
		else:
			var sql = "INSERT INTO schedule_entries (entry_uuid, person_name, person_id, shift_role, shift_date, start_time, end_time, area, notes) VALUES (hex(randomblob(16)), ?, ?, ?, ?, ?, ?, ?, ?);"
			db.execute(sql, [payload["person_name"], payload["person_id"], payload["shift_role"], payload["shift_date"], payload["start_time"], payload["end_time"], payload["area"], payload["notes"]])

		if queue_controller:
			queue_controller.start_queue(active_queue_id)
		_refresh_queue_view()
		dlg.queue_free()
	)
	dlg.assignment_cancelled.connect(func():
		dlg.queue_free()
	)

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig = MigrationsRunnerScript.new(db)
		mig.run_migrations()
	if not sch_service:
		sch_service = SchedulesServiceScript.new(db)
	
	db.execute("""
		CREATE TABLE IF NOT EXISTS center_hour_overrides (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			override_date TEXT UNIQUE NOT NULL,
			is_closed INTEGER NOT NULL DEFAULT 0,
			session1_start TEXT NOT NULL DEFAULT '03:00 PM',
			session1_end TEXT NOT NULL DEFAULT '08:00 PM',
			has_split_shift INTEGER NOT NULL DEFAULT 0,
			session2_start TEXT DEFAULT NULL,
			session2_end TEXT DEFAULT NULL
		);
	""")

func _setup_marquee_and_preview_overlay() -> void:
	marquee_rect_control = ColorRect.new()
	marquee_rect_control.color = Color(0.88, 0.35, 0.21, 0.30)
	marquee_rect_control.visible = false
	marquee_rect_control.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(marquee_rect_control)

	drop_indicator_line = ColorRect.new()
	drop_indicator_line.color = Color(0.88, 0.35, 0.21, 1.0)
	drop_indicator_line.visible = false
	drop_indicator_line.mouse_filter = MOUSE_FILTER_IGNORE
	drop_indicator_line.custom_minimum_size = Vector2(0, 4)
	add_child(drop_indicator_line)

	drag_preview_label = Label.new()
	drag_preview_label.visible = false
	drag_preview_label.mouse_filter = MOUSE_FILTER_IGNORE
	drag_preview_label.add_theme_font_size_override("font_size", 13)
	drag_preview_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.88, 0.35, 0.21, 0.95)
	st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
	st.content_margin_left = 10; st.content_margin_top = 6; st.content_margin_right = 10; st.content_margin_bottom = 6
	drag_preview_label.add_theme_stylebox_override("normal", st)
	add_child(drag_preview_label)

func _style_card() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.91, 0.95, 1.0)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 18; style.content_margin_top = 16; style.content_margin_right = 18; style.content_margin_bottom = 16
	content_card.add_theme_stylebox_override("panel", style)

func _connect_tab_buttons() -> void:
	if btn_tab_shifts: btn_tab_shifts.pressed.connect(func(): switch_top_tab("shifts"))
	if btn_tab_sessions: btn_tab_sessions.pressed.connect(func(): switch_top_tab("sessions"))
	if btn_tab_hours: btn_tab_hours.pressed.connect(func(): switch_top_tab("hours"))

func switch_top_tab(tab_name: String) -> void:
	active_top_tab = tab_name
	_update_top_tab_styles()
	call_deferred("_refresh_tab_content")

func _update_top_tab_styles() -> void:
	_style_tab_btn(btn_tab_shifts, active_top_tab == "shifts")
	_style_tab_btn(btn_tab_sessions, active_top_tab == "sessions")
	_style_tab_btn(btn_tab_hours, active_top_tab == "hours")

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

func _get_active_secondary_color() -> Color:
	var idx = 0
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "0"))

	if idx == 0:
		return Color(0.737, 0.635, 0.439, 1.0) # AU Gold #BCA270
	return _get_active_theme_color()

func _style_tab_btn(btn: Button, is_active: bool) -> void:
	if not btn: return
	var primary_col = _get_active_theme_color()
	var sec_col = _get_active_secondary_color()

	var st = StyleBoxFlat.new()
	st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
	
	var st_hover = StyleBoxFlat.new()
	st_hover.corner_radius_top_left = 6; st_hover.corner_radius_top_right = 6; st_hover.corner_radius_bottom_left = 6; st_hover.corner_radius_bottom_right = 6
	
	if is_active:
		st.bg_color = primary_col
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		
		st_hover.bg_color = primary_col.lightened(0.08)
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	else:
		st.bg_color = Color(0.94, 0.96, 0.98, 1.0)
		btn.add_theme_color_override("font_color", Color(0.30, 0.38, 0.48, 1.0))
		
		st_hover.bg_color = Color(0.97, 0.98, 1.0, 1.0)
		st_hover.border_width_left = 1; st_hover.border_width_top = 1; st_hover.border_width_right = 1; st_hover.border_width_bottom = 1
		st_hover.border_color = sec_col
		btn.add_theme_color_override("font_hover_color", primary_col)
		
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", st_hover)
	
	var st_pressed = StyleBoxFlat.new()
	st_pressed.corner_radius_top_left = 6; st_pressed.corner_radius_top_right = 6; st_pressed.corner_radius_bottom_left = 6; st_pressed.corner_radius_bottom_right = 6
	st_pressed.bg_color = Color(0.80, 0.30, 0.18, 1.0)
	btn.add_theme_stylebox_override("pressed", st_pressed)

func get_date_string_for_day_index(day_idx: int) -> String:
	if current_week_base_unix == 0:
		current_week_base_unix = Time.get_unix_time_from_datetime_string("2026-07-19T12:00:00")
	var target_unix = current_week_base_unix + (day_idx * 86400)
	var dict = Time.get_datetime_dict_from_unix_time(target_unix)
	return "%04d-%02d-%02d" % [dict["year"], dict["month"], dict["day"]]

func get_day_index_from_date_string(date_str: String) -> int:
	if date_str.strip_edges() == "": return 0
	var unix = Time.get_unix_time_from_datetime_string(date_str + "T12:00:00")
	if unix <= 0: return 0
	var dict = Time.get_datetime_dict_from_unix_time(unix)
	return int(dict.get("weekday", 0))

func get_weekday_name_for_date_string(date_str: String) -> String:
	var day_idx = get_day_index_from_date_string(date_str)
	return DAYS_META[day_idx]["code"]

func get_hour_override_for_date(date_str: String) -> Dictionary:
	if not db: return {}
	var res = db.execute("SELECT is_closed, session1_start, session1_end, has_split_shift, session2_start, session2_end FROM center_hour_overrides WHERE override_date = ? LIMIT 1;", [date_str])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {}

func save_hour_override(date_str: String, is_closed: int, s1_start: String, s1_end: String, has_split: int, s2_start: String, s2_end: String) -> void:
	if not db: return
	db.execute("INSERT OR REPLACE INTO center_hour_overrides (override_date, is_closed, session1_start, session1_end, has_split_shift, session2_start, session2_end) VALUES (?, ?, ?, ?, ?, ?, ?);", [
		date_str, is_closed, s1_start, s1_end, has_split, s2_start, s2_end
	])

func delete_hour_override(date_str: String) -> void:
	if not db: return
	db.execute("DELETE FROM center_hour_overrides WHERE override_date = ?;", [date_str])

func open_hours_override_modal(day_name: String, date_str: String) -> void:
	var existing = get_hour_override_for_date(date_str)
	var is_override_enabled = (existing.size() > 0)

	var dialog = Window.new()
	dialog.title = "📅 Override Hours: " + day_name + " (" + date_str + ")"
	dialog.size = Vector2i(540, 520)
	dialog.exclusive = true
	dialog.transient = true
	dialog.close_requested.connect(func(): dialog.queue_free())

	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)

	var mvbox = VBoxContainer.new(); mvbox.add_theme_constant_override("separation", 14)

	var chk_enable = CheckBox.new()
	chk_enable.text = "Enable Date-Specific Hours Override"
	chk_enable.button_pressed = is_override_enabled
	mvbox.add_child(chk_enable)

	var form_vbox = VBoxContainer.new(); form_vbox.add_theme_constant_override("separation", 12)
	mvbox.add_child(form_vbox)

	var lbl_status = Label.new(); lbl_status.text = "Day Status:"; lbl_status.add_theme_font_size_override("font_size", 13)
	form_vbox.add_child(lbl_status)

	var opt_status = OptionButton.new(); opt_status.custom_minimum_size = Vector2(0, 36)
	opt_status.add_item("Open", 0)
	opt_status.add_item("Closed", 1)
	var initial_closed = int(existing.get("is_closed", 0)) == 1
	opt_status.select(1 if initial_closed else 0)
	form_vbox.add_child(opt_status)

	var s1_vbox = VBoxContainer.new(); s1_vbox.add_theme_constant_override("separation", 6)
	var lbl_s1 = Label.new(); lbl_s1.text = "Operating Session 1:"; lbl_s1.add_theme_font_size_override("font_size", 13)
	s1_vbox.add_child(lbl_s1)

	var s1_hbox = HBoxContainer.new(); s1_hbox.add_theme_constant_override("separation", 8)
	var opt_s1_start = OptionButton.new(); opt_s1_start.size_flags_horizontal = SIZE_EXPAND_FILL; opt_s1_start.custom_minimum_size = Vector2(0, 36)
	for t in STANDARD_TIME_SLOTS: opt_s1_start.add_item(t)
	s1_hbox.add_child(opt_s1_start)

	var opt_s1_end = OptionButton.new(); opt_s1_end.size_flags_horizontal = SIZE_EXPAND_FILL; opt_s1_end.custom_minimum_size = Vector2(0, 36)
	for t in STANDARD_TIME_SLOTS: opt_s1_end.add_item(t)
	s1_hbox.add_child(opt_s1_end)
	s1_vbox.add_child(s1_hbox)
	form_vbox.add_child(s1_vbox)

	var chk_split = CheckBox.new()
	chk_split.text = "Add Second Session (Split Shift)"
	var initial_split = int(existing.get("has_split_shift", 0)) == 1
	chk_split.button_pressed = initial_split
	form_vbox.add_child(chk_split)

	var s2_vbox = VBoxContainer.new(); s2_vbox.add_theme_constant_override("separation", 6)
	var lbl_s2 = Label.new(); lbl_s2.text = "Operating Session 2 (Split Shift):"; lbl_s2.add_theme_font_size_override("font_size", 13)
	s2_vbox.add_child(lbl_s2)

	var s2_hbox = HBoxContainer.new(); s2_hbox.add_theme_constant_override("separation", 8)
	var opt_s2_start = OptionButton.new(); opt_s2_start.size_flags_horizontal = SIZE_EXPAND_FILL; opt_s2_start.custom_minimum_size = Vector2(0, 36)
	for t in STANDARD_TIME_SLOTS: opt_s2_start.add_item(t)
	s2_hbox.add_child(opt_s2_start)

	var opt_s2_end = OptionButton.new(); opt_s2_end.size_flags_horizontal = SIZE_EXPAND_FILL; opt_s2_end.custom_minimum_size = Vector2(0, 36)
	for t in STANDARD_TIME_SLOTS: opt_s2_end.add_item(t)
	s2_hbox.add_child(opt_s2_end)
	s2_vbox.add_child(s2_hbox)
	form_vbox.add_child(s2_vbox)

	var cur_s1_start = str(existing.get("session1_start", "09:00 AM"))
	var cur_s1_end = str(existing.get("session1_end", "12:00 PM"))
	var cur_s2_start = str(existing.get("session2_start", "03:00 PM"))
	var cur_s2_end = str(existing.get("session2_end", "08:00 PM"))

	for i in range(STANDARD_TIME_SLOTS.size()):
		if STANDARD_TIME_SLOTS[i] == cur_s1_start: opt_s1_start.select(i)
		if STANDARD_TIME_SLOTS[i] == cur_s1_end: opt_s1_end.select(i)
		if STANDARD_TIME_SLOTS[i] == cur_s2_start: opt_s2_start.select(i)
		if STANDARD_TIME_SLOTS[i] == cur_s2_end: opt_s2_end.select(i)

	var update_ui_states = func(val = 0):
		var main_enabled = chk_enable.button_pressed
		form_vbox.visible = main_enabled
		if main_enabled:
			var closed = (opt_status.selected == 1)
			s1_vbox.visible = not closed
			chk_split.visible = not closed
			s2_vbox.visible = (not closed and chk_split.button_pressed)

	chk_enable.toggled.connect(update_ui_states)
	opt_status.item_selected.connect(update_ui_states)
	chk_split.toggled.connect(update_ui_states)
	update_ui_states.call()

	var spacer = Control.new(); spacer.custom_minimum_size = Vector2(0, 10)
	mvbox.add_child(spacer)

	var btn_hbox = HBoxContainer.new(); btn_hbox.add_theme_constant_override("separation", 14); btn_hbox.alignment = BoxContainer.ALIGNMENT_END

	var btn_cancel = Button.new(); btn_cancel.text = "Cancel"; btn_cancel.custom_minimum_size = Vector2(100, 38)
	_style_outline_button(btn_cancel)
	btn_cancel.pressed.connect(func(): dialog.queue_free())
	btn_hbox.add_child(btn_cancel)

	var btn_save = Button.new(); btn_save.text = "💾 Save Override"; btn_save.custom_minimum_size = Vector2(140, 38)
	var s_st = StyleBoxFlat.new(); s_st.bg_color = Color(0.88, 0.35, 0.21, 1.0); s_st.corner_radius_top_left = 8; s_st.corner_radius_top_right = 8; s_st.corner_radius_bottom_left = 8; s_st.corner_radius_bottom_right = 8
	btn_save.add_theme_stylebox_override("normal", s_st)
	btn_save.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_save.pressed.connect(func():
		if chk_enable.button_pressed:
			var cl = opt_status.selected
			var s1_s = opt_s1_start.get_item_text(opt_s1_start.selected)
			var s1_e = opt_s1_end.get_item_text(opt_s1_end.selected)
			var split = 1 if chk_split.button_pressed else 0
			var s2_s = opt_s2_start.get_item_text(opt_s2_start.selected)
			var s2_e = opt_s2_end.get_item_text(opt_s2_end.selected)
			save_hour_override(date_str, cl, s1_s, s1_e, split, s2_s, s2_e)
		else:
			delete_hour_override(date_str)

		dialog.queue_free()
		call_deferred("_refresh_tab_content")
	)
	btn_hbox.add_child(btn_save)

	mvbox.add_child(btn_hbox)
	margin.add_child(mvbox)
	dialog.add_child(margin)

	add_child(dialog)
	dialog.popup_centered()

func _get_all_center_members() -> Array:
	if not db: return []
	var res = db.execute("SELECT id, entry_uuid, first_name, last_name, primary_role FROM people ORDER BY last_name ASC, first_name ASC;")
	if res["success"] and res["data"].size() > 0:
		return res["data"]

	return [
		{"first_name": "John", "last_name": "Smith", "primary_role": "Staff"},
		{"first_name": "Sarah", "last_name": "Johnson", "primary_role": "Intern"},
		{"first_name": "Michael", "last_name": "Brown", "primary_role": "Volunteer"},
		{"first_name": "Emily", "last_name": "Davis", "primary_role": "Student"},
		{"first_name": "David", "last_name": "Wilson", "primary_role": "Staff"},
		{"first_name": "Jessica", "last_name": "Taylor", "primary_role": "Volunteer"}
	]

# ==================== DUAL GESTURE & REARRANGING ENGINE ====================

func _input(event: InputEvent) -> void:
	if active_top_tab != "shifts" or active_shift_view_mode != "board": return

	var focus_owner = get_viewport().gui_get_focus_owner()
	if focus_owner and (focus_owner is LineEdit or focus_owner is TextEdit):
		return

	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_global_mouse_press(mb)
			else:
				_handle_global_mouse_release(mb)

	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		_handle_global_mouse_motion(mm)

	elif event is InputEventKey and event.pressed:
		var k = event as InputEventKey
		if k.is_command_or_control_pressed():
			if k.keycode == KEY_C: _copy_selected_shifts(); get_viewport().set_input_as_handled()
			elif k.keycode == KEY_X: _cut_selected_shifts(); get_viewport().set_input_as_handled()
			elif k.keycode == KEY_V: _paste_clipboard_shifts(); get_viewport().set_input_as_handled()
			elif k.keycode == KEY_A: _select_all_shifts(); get_viewport().set_input_as_handled()
		elif k.keycode == KEY_BACKSPACE or k.keycode == KEY_DELETE:
			_delete_selected_shifts(); get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE:
			_clear_selection_and_clipboard(); get_viewport().set_input_as_handled()

func _handle_global_mouse_press(mb: InputEventMouseButton) -> void:
	drag_start_global = mb.global_position
	press_start_msec = Time.get_ticks_msec()
	current_gesture_mode = GestureMode.GESTURE_NONE

	var clicked_card = _find_card_at_pos(mb.global_position)
	if clicked_card:
		initial_click_shift_uuid = str(clicked_card.shift_data.get("entry_uuid"))
		select_shift_by_id(initial_click_shift_uuid, mb.shift_pressed, mb.is_command_or_control_pressed())
		drag_source_shift_uuids = selected_shift_ids.keys()
	else:
		initial_click_shift_uuid = ""
		drag_source_shift_uuids.clear()

func _handle_global_mouse_motion(mm: InputEventMouseMotion) -> void:
	if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		var dist = drag_start_global.distance_to(mm.global_position)
		var elapsed_ms = Time.get_ticks_msec() - press_start_msec

		if current_gesture_mode == GestureMode.GESTURE_NONE and dist > 6:
			if elapsed_ms >= 250 and initial_click_shift_uuid != "":
				current_gesture_mode = GestureMode.GESTURE_CARD_DRAG
				drag_preview_label.visible = true
			else:
				current_gesture_mode = GestureMode.GESTURE_MARQUEE_SELECT
				marquee_rect_control.visible = true

		if current_gesture_mode == GestureMode.GESTURE_MARQUEE_SELECT:
			var min_x = min(drag_start_global.x, mm.global_position.x)
			var min_y = min(drag_start_global.y, mm.global_position.y)
			var max_x = max(drag_start_global.x, mm.global_position.x)
			var max_y = max(drag_start_global.y, mm.global_position.y)

			marquee_rect_control.position = Vector2(min_x, min_y) - global_position
			marquee_rect_control.size = Vector2(max_x - min_x, max_y - min_y)

			var drag_rect = Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
			_update_marquee_selection(drag_rect, mm.is_command_or_control_pressed())

		elif current_gesture_mode == GestureMode.GESTURE_CARD_DRAG:
			drag_preview_label.position = mm.global_position - global_position + Vector2(12, 12)
			var count = max(1, drag_source_shift_uuids.size())
			drag_preview_label.text = " 👥 Rearranging " + str(count) + " shift(s) "

			var target_col = _find_day_column_at_pos(mm.global_position)
			if target_col:
				var col_rect = target_col.get_global_rect()
				var insert_y = col_rect.position.y + col_rect.size.y - 12
				var cards_in_col = _get_cards_in_column(target_col, drag_source_shift_uuids)

				for card in cards_in_col:
					var card_rect = card.get_global_rect()
					if mm.global_position.y < card_rect.get_center().y:
						insert_y = card_rect.position.y - 3
						break

				drop_indicator_line.position = Vector2(col_rect.position.x + 4, insert_y) - global_position
				drop_indicator_line.size = Vector2(col_rect.size.x - 8, 4)
				drop_indicator_line.visible = true
			else:
				drop_indicator_line.visible = false

func _handle_global_mouse_release(mb: InputEventMouseButton) -> void:
	if current_gesture_mode == GestureMode.GESTURE_CARD_DRAG and drag_source_shift_uuids.size() > 0:
		var target_col = _find_day_column_at_pos(mb.global_position)
		if target_col:
			var target_date_s = get_date_string_for_day_index(target_col.day_index)
			var existing_cards = _get_cards_in_column(target_col, drag_source_shift_uuids)

			var insert_idx = existing_cards.size()
			for i in range(existing_cards.size()):
				var card_rect = existing_cards[i].get_global_rect()
				if mb.global_position.y < card_rect.get_center().y:
					insert_idx = i
					break

			var new_ordered_uuids = []
			for i in range(existing_cards.size()):
				if i == insert_idx:
					for u in drag_source_shift_uuids:
						new_ordered_uuids.append(str(u))
				new_ordered_uuids.append(str(existing_cards[i].shift_data.get("entry_uuid")))

			if insert_idx >= existing_cards.size():
				for u in drag_source_shift_uuids:
					new_ordered_uuids.append(str(u))

			sch_service.reorder_shifts_in_day_atomic(target_date_s, new_ordered_uuids)

	current_gesture_mode = GestureMode.GESTURE_NONE
	drag_source_shift_uuids.clear()
	initial_click_shift_uuid = ""
	if marquee_rect_control: marquee_rect_control.visible = false
	if drag_preview_label: drag_preview_label.visible = false
	if drop_indicator_line: drop_indicator_line.visible = false

	call_deferred("_refresh_tab_content")

func _get_cards_in_column(col: DayColumnControl, exclude_uuids: Array) -> Array:
	var result = []
	var exclude_set = {}
	for u in exclude_uuids: exclude_set[str(u)] = true

	for card in all_card_nodes:
		if is_instance_valid(card) and card is ShiftCardControl:
			var s_date = str(card.shift_data.get("shift_date", ""))
			var day_idx = get_day_index_from_date_string(s_date)
			var u = str(card.shift_data.get("entry_uuid"))

			if day_idx == col.day_index and not exclude_set.has(u):
				result.append(card)

	result.sort_custom(func(a, b):
		return a.get_global_rect().position.y < b.get_global_rect().position.y
	)
	return result

func _find_card_at_pos(global_pos: Vector2) -> ShiftCardControl:
	for card in all_card_nodes:
		if is_instance_valid(card) and card is ShiftCardControl:
			if card.get_global_rect().has_point(global_pos):
				return card
	return null

func _find_day_column_at_pos(global_pos: Vector2) -> DayColumnControl:
	for col in all_day_columns:
		if is_instance_valid(col) and col is DayColumnControl:
			if col.get_global_rect().has_point(global_pos):
				return col
	return null

func _update_marquee_selection(drag_global_rect: Rect2, append_mode: bool) -> void:
	if not append_mode:
		selected_shift_ids.clear()

	for card in all_card_nodes:
		if is_instance_valid(card) and card is ShiftCardControl:
			if drag_global_rect.intersects(card.get_global_rect()):
				var u = str(card.shift_data.get("entry_uuid"))
				selected_shift_ids[u] = true

func _clear_selection_and_clipboard() -> void:
	selected_shift_ids.clear()
	selection_anchor_id = ""
	clipboard.clear()
	if marquee_rect_control: marquee_rect_control.visible = false
	if drag_preview_label: drag_preview_label.visible = false
	if drop_indicator_line: drop_indicator_line.visible = false
	call_deferred("_refresh_tab_content")

func _select_all_shifts() -> void:
	if not sch_service: return
	var start_d = get_date_string_for_day_index(0)
	var end_d = get_date_string_for_day_index(6)
	var shifts = sch_service.get_shift_entries_for_range(start_d, end_d)
	selected_shift_ids.clear()
	for s in shifts:
		selected_shift_ids[str(s.get("entry_uuid"))] = true
	call_deferred("_refresh_tab_content")

func open_shift_context_menu(shift_data: Dictionary, global_pos: Vector2) -> void:
	var s_uuid = str(shift_data.get("entry_uuid"))
	if not selected_shift_ids.has(s_uuid):
		selected_shift_ids = {s_uuid: true}
		selection_anchor_id = s_uuid
		call_deferred("_refresh_tab_content")

	var menu = PopupMenu.new()
	menu.add_item("✏️ Edit Shift", 4)
	menu.add_separator()
	menu.add_item("🗑️ Delete Selected (Del)", 3)

	menu.id_pressed.connect(func(id):
		if id == 4: open_shift_modal(shift_data)
		elif id == 3: _prompt_delete_shift_dialog(shift_data)
		menu.queue_free()
	)
	add_child(menu)
	menu.position = Vector2i(global_pos)
	menu.popup()

func _refresh_tab_content() -> void:
	if not db: return
	if not sch_service: sch_service = SchedulesServiceScript.new(db)

	all_card_nodes.clear()
	all_day_columns.clear()
	for child in content_card.get_children():
		child.queue_free()

	if active_top_tab == "shifts":
		_render_shifts_tab()
	elif active_top_tab == "sessions":
		_render_sessions_tab()
	elif active_top_tab == "hours":
		_render_hours_tab()

# ==================== TAB 1: STAFFING SCHEDULE ====================

func update_hours_by_day_name(day_name: String, open_time: String, close_time: String, is_closed: int, has_split_shift: int = 0, session2_start: String = "05:00 PM", session2_end: String = "08:00 PM") -> void:
	if not db: return
	var sql = "UPDATE center_open_hours SET open_time = ?, close_time = ?, is_closed = ?, has_split_shift = ?, session2_start = ?, session2_end = ? WHERE day_of_week = ?;"
	db.execute(sql, [open_time, close_time, is_closed, has_split_shift, session2_start, session2_end, day_name])

func _render_shifts_tab() -> void:
	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 14)

	# Fetch Center Operating Hours Map
	var hours_data = {}
	var open_hours = sch_service.get_open_hours()
	for h in open_hours:
		hours_data[str(h.get("day_of_week"))] = h

	# Row 1: View Mode Switcher + Add Shift Button
	var view_toggle_hbox = HBoxContainer.new(); view_toggle_hbox.add_theme_constant_override("separation", 10)

	var btn_table_view = Button.new()
	btn_table_view.text = "Table View"
	btn_table_view.custom_minimum_size = Vector2(110, 36)
	_style_pill_button(btn_table_view, active_shift_view_mode == "table")
	btn_table_view.pressed.connect(func():
		active_shift_view_mode = "table"
		call_deferred("_refresh_tab_content")
	)
	view_toggle_hbox.add_child(btn_table_view)

	var btn_board_view = Button.new()
	btn_board_view.text = "Week Board View"
	btn_board_view.custom_minimum_size = Vector2(140, 36)
	_style_pill_button(btn_board_view, active_shift_view_mode == "board")
	btn_board_view.pressed.connect(func():
		active_shift_view_mode = "board"
		call_deferred("_refresh_tab_content")
	)
	view_toggle_hbox.add_child(btn_board_view)

	var spacer = Control.new(); spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	view_toggle_hbox.add_child(spacer)

	var btn_add_shift_modal = Button.new()
	btn_add_shift_modal.text = "➕ Add Shift"
	btn_add_shift_modal.custom_minimum_size = Vector2(130, 36)
	var add_st = StyleBoxFlat.new()
	add_st.bg_color = _get_active_theme_color(); add_st.corner_radius_top_left = 18; add_st.corner_radius_top_right = 18; add_st.corner_radius_bottom_left = 18; add_st.corner_radius_bottom_right = 18
	btn_add_shift_modal.add_theme_stylebox_override("normal", add_st)
	btn_add_shift_modal.add_theme_stylebox_override("hover", add_st)
	btn_add_shift_modal.add_theme_stylebox_override("pressed", add_st)
	btn_add_shift_modal.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn_add_shift_modal.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn_add_shift_modal.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn_add_shift_modal.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
	btn_add_shift_modal.pressed.connect(func(): open_shift_modal({}))
	view_toggle_hbox.add_child(btn_add_shift_modal)

	vbox.add_child(view_toggle_hbox)

	# Row 2: Action Toolbar
	var toolbar_hbox = HBoxContainer.new(); toolbar_hbox.add_theme_constant_override("separation", 10)
	toolbar_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	var btn_prev = Button.new(); btn_prev.text = "← Previous"; btn_prev.custom_minimum_size = Vector2(100, 34)
	_style_outline_button(btn_prev)
	btn_prev.pressed.connect(func():
		if current_week_base_unix == 0:
			current_week_base_unix = Time.get_unix_time_from_datetime_string("2026-07-19T12:00:00")
		current_week_base_unix -= 7 * 86400
		call_deferred("_refresh_tab_content")
	)
	toolbar_hbox.add_child(btn_prev)

	var btn_today = Button.new(); btn_today.text = "Today"; btn_today.custom_minimum_size = Vector2(75, 34)
	_style_outline_button(btn_today)
	btn_today.pressed.connect(func():
		current_week_base_unix = Time.get_unix_time_from_datetime_string("2026-07-19T12:00:00")
		call_deferred("_refresh_tab_content")
	)
	toolbar_hbox.add_child(btn_today)

	var btn_next = Button.new(); btn_next.text = "Next →"; btn_next.custom_minimum_size = Vector2(90, 34)
	_style_outline_button(btn_next)
	btn_next.pressed.connect(func():
		if current_week_base_unix == 0:
			current_week_base_unix = Time.get_unix_time_from_datetime_string("2026-07-19T12:00:00")
		current_week_base_unix += 7 * 86400
		call_deferred("_refresh_tab_content")
	)
	toolbar_hbox.add_child(btn_next)

	var range_spacer = Control.new(); range_spacer.custom_minimum_size = Vector2(8, 0)
	toolbar_hbox.add_child(range_spacer)

	var lbl_range = Label.new()
	lbl_range.text = _get_current_week_range_string()
	lbl_range.add_theme_font_size_override("font_size", 14)
	lbl_range.add_theme_color_override("font_color", Color(0.18, 0.24, 0.32, 1.0))
	lbl_range.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar_hbox.add_child(lbl_range)

	var num_selected = selected_shift_ids.size()

	vbox.add_child(toolbar_hbox)

	# Collapsible Normal Hour Selector Header
	var hour_selector_panel = PanelContainer.new(); hour_selector_panel.custom_minimum_size = Vector2(0, 40)
	var hst = StyleBoxFlat.new()
	hst.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	hst.border_width_left = 1; hst.border_width_top = 1; hst.border_width_right = 1; hst.border_width_bottom = 1
	hst.border_color = Color(0.88, 0.91, 0.95, 1.0)
	hst.corner_radius_top_left = 8; hst.corner_radius_top_right = 8; hst.corner_radius_bottom_left = 8; hst.corner_radius_bottom_right = 8
	hst.content_margin_left = 16; hst.content_margin_top = 8; hst.content_margin_right = 16; hst.content_margin_bottom = 8
	hour_selector_panel.add_theme_stylebox_override("panel", hst)

	var hhbox = HBoxContainer.new()
	var h_title = Label.new(); h_title.text = "Normal Hour Selector"; h_title.size_flags_horizontal = SIZE_EXPAND_FILL
	h_title.add_theme_font_size_override("font_size", 14); h_title.add_theme_color_override("font_color", Color(0.18, 0.24, 0.32, 1.0))
	hhbox.add_child(h_title)

	var btn_toggle_hours = Button.new()
	btn_toggle_hours.text = "Hide" if is_hours_selector_visible else "Show"
	btn_toggle_hours.flat = true
	btn_toggle_hours.add_theme_font_size_override("font_size", 14)
	
	# Keep text visible and bold on hover
	btn_toggle_hours.add_theme_color_override("font_color", Color(0.28, 0.34, 0.42, 1.0))
	btn_toggle_hours.add_theme_color_override("font_hover_color", Color(0.88, 0.35, 0.21, 1.0))
	btn_toggle_hours.add_theme_color_override("font_pressed_color", Color(0.88, 0.35, 0.21, 1.0))
	btn_toggle_hours.add_theme_color_override("font_focus_color", Color(0.28, 0.34, 0.42, 1.0))
	
	# Transparent backgrounds so flat aesthetic is preserved perfectly
	var toggle_style = StyleBoxFlat.new()
	toggle_style.bg_color = Color(1, 1, 1, 0)
	btn_toggle_hours.add_theme_stylebox_override("normal", toggle_style)
	btn_toggle_hours.add_theme_stylebox_override("hover", toggle_style)
	btn_toggle_hours.add_theme_stylebox_override("pressed", toggle_style)
	btn_toggle_hours.add_theme_stylebox_override("focus", toggle_style)

	btn_toggle_hours.pressed.connect(func():
		is_hours_selector_visible = not is_hours_selector_visible
		call_deferred("_refresh_tab_content")
	)
	hhbox.add_child(btn_toggle_hours)
	hour_selector_panel.add_child(hhbox)
	vbox.add_child(hour_selector_panel)

	# Beautifully styled normal hours selector grid matching screenshot!
	if is_hours_selector_visible:
		var hours_grid_vbox = VBoxContainer.new()
		hours_grid_vbox.add_theme_constant_override("separation", 10)
		_build_hours_selector_grid(hours_grid_vbox, hours_data)
		vbox.add_child(hours_grid_vbox)

	var main_panel = PanelContainer.new(); main_panel.size_flags_vertical = SIZE_EXPAND_FILL

	if active_shift_view_mode == "board":
		_render_shift_cards(main_panel, hours_data)
	else:
		_render_shift_table(main_panel)

	vbox.add_child(main_panel)
	content_card.add_child(vbox)

func _build_hours_selector_grid(container: VBoxContainer, hours_data: Dictionary) -> void:
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)

	var ordered_days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

	for day_name in ordered_days:
		var h = hours_data.get(day_name, {"open_time": "09:00 AM", "close_time": "06:00 PM", "is_closed": 0, "has_split_shift": 0, "session2_start": "05:00 PM", "session2_end": "08:00 PM"})
		var open_t = str(h.get("open_time", "09:00 AM"))
		var close_t = str(h.get("close_time", "06:00 PM"))
		var is_closed = int(h.get("is_closed", 0)) == 1
		var has_split = int(h.get("has_split_shift", 0)) == 1
		var s2_start_t = str(h.get("session2_start", "05:00 PM"))
		var s2_end_t = str(h.get("session2_end", "08:00 PM"))

		var card = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
		st.border_color = Color(0.88, 0.91, 0.95, 1.0)
		st.corner_radius_top_left = 12; st.corner_radius_top_right = 12; st.corner_radius_bottom_left = 12; st.corner_radius_bottom_right = 12
		st.content_margin_left = 16; st.content_margin_top = 14; st.content_margin_right = 16; st.content_margin_bottom = 14
		card.add_theme_stylebox_override("panel", st)

		var cvbox = VBoxContainer.new(); cvbox.add_theme_constant_override("separation", 8)

		# Row 1: Title & Open Checkbox
		var r1_hbox = HBoxContainer.new()
		var title_lbl = Label.new(); title_lbl.text = "Normal " + day_name + " Hours"; title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		title_lbl.add_theme_font_size_override("font_size", 14); title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
		r1_hbox.add_child(title_lbl)

		var chk_open = CheckBox.new(); chk_open.text = "Open"; chk_open.button_pressed = not is_closed
		chk_open.add_theme_font_size_override("font_size", 13)
		r1_hbox.add_child(chk_open)
		cvbox.add_child(r1_hbox)

		# Row 2: Session 1 Selectors
		var time_hbox = HBoxContainer.new(); time_hbox.add_theme_constant_override("separation", 8)

		var start_opt = OptionButton.new(); start_opt.size_flags_horizontal = SIZE_EXPAND_FILL; start_opt.custom_minimum_size = Vector2(0, 34)
		for t in STANDARD_TIME_SLOTS: start_opt.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == open_t: start_opt.select(i)
		time_hbox.add_child(start_opt)

		var end_opt = OptionButton.new(); end_opt.size_flags_horizontal = SIZE_EXPAND_FILL; end_opt.custom_minimum_size = Vector2(0, 34)
		for t in STANDARD_TIME_SLOTS: end_opt.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == close_t: end_opt.select(i)
		time_hbox.add_child(end_opt)
		cvbox.add_child(time_hbox)

		# Row 3: Split Shift Checkbox
		var chk_split = CheckBox.new(); chk_split.text = "Split Shift (2 Sessions)"; chk_split.button_pressed = has_split
		chk_split.add_theme_font_size_override("font_size", 12)
		cvbox.add_child(chk_split)

		# Row 4: Session 2 Selectors
		var time2_hbox = HBoxContainer.new(); time2_hbox.add_theme_constant_override("separation", 8)

		var s2_start_opt = OptionButton.new(); s2_start_opt.size_flags_horizontal = SIZE_EXPAND_FILL; s2_start_opt.custom_minimum_size = Vector2(0, 34)
		for t in STANDARD_TIME_SLOTS: s2_start_opt.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == s2_start_t: s2_start_opt.select(i)
		time2_hbox.add_child(s2_start_opt)

		var s2_end_opt = OptionButton.new(); s2_end_opt.size_flags_horizontal = SIZE_EXPAND_FILL; s2_end_opt.custom_minimum_size = Vector2(0, 34)
		for t in STANDARD_TIME_SLOTS: s2_end_opt.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == s2_end_t: s2_end_opt.select(i)
		time2_hbox.add_child(s2_end_opt)
		cvbox.add_child(time2_hbox)

		# Row 5: Status Indicator Label
		var status_lbl = Label.new()
		status_lbl.add_theme_font_size_override("font_size", 11)
		status_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.68, 1.0))
		cvbox.add_child(status_lbl)

		var refresh_ui_states = func():
			var is_open = chk_open.button_pressed
			var is_split = chk_split.button_pressed and is_open

			start_opt.disabled = not is_open
			end_opt.disabled = not is_open
			chk_split.disabled = not is_open
			s2_start_opt.disabled = not is_split
			s2_end_opt.disabled = not is_split

			if not is_open:
				status_lbl.text = day_name + " Hours: Closed"
			elif is_split:
				status_lbl.text = day_name + " Hours: " + start_opt.get_item_text(start_opt.selected) + "-" + end_opt.get_item_text(end_opt.selected) + " & " + s2_start_opt.get_item_text(s2_start_opt.selected) + "-" + s2_end_opt.get_item_text(s2_end_opt.selected)
			else:
				status_lbl.text = day_name + " Hours: " + start_opt.get_item_text(start_opt.selected) + " to " + end_opt.get_item_text(end_opt.selected)

		refresh_ui_states.call()

		var save_changes = func(val = 0):
			refresh_ui_states.call()
			var closed_val = 0 if chk_open.button_pressed else 1
			var split_val = 1 if (chk_split.button_pressed and chk_open.button_pressed) else 0
			var open_str = start_opt.get_item_text(start_opt.selected)
			var close_str = end_opt.get_item_text(end_opt.selected)
			var s2_start_str = s2_start_opt.get_item_text(s2_start_opt.selected)
			var s2_end_str = s2_end_opt.get_item_text(s2_end_opt.selected)
			update_hours_by_day_name(day_name, open_str, close_str, closed_val, split_val, s2_start_str, s2_end_str)

		chk_open.toggled.connect(save_changes)
		chk_split.toggled.connect(save_changes)
		start_opt.item_selected.connect(save_changes)
		end_opt.item_selected.connect(save_changes)
		s2_start_opt.item_selected.connect(save_changes)
		s2_end_opt.item_selected.connect(save_changes)

		card.add_child(cvbox)
		grid.add_child(card)

	container.add_child(grid)

	var footer_lbl = Label.new()
	footer_lbl.text = "Foundation Hours auto-save as you edit."
	footer_lbl.add_theme_font_size_override("font_size", 12)
	footer_lbl.add_theme_color_override("font_color", Color(0.40, 0.48, 0.58, 1.0))
	container.add_child(footer_lbl)

# ==================== ADD & EDIT SHIFT MODAL DIALOG ====================

func open_shift_modal(existing_shift_data: Dictionary = {}) -> void:
	var is_edit_mode = (existing_shift_data.size() > 0 and existing_shift_data.has("entry_uuid"))

	var dialog = Window.new()
	dialog.title = "✏️ Edit Shift Entry" if is_edit_mode else "➕ Add New Shift Entry"
	dialog.size = Vector2i(560, 580)
	dialog.exclusive = true
	dialog.transient = true
	dialog.close_requested.connect(func(): dialog.queue_free())

	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)

	var mvbox = VBoxContainer.new(); mvbox.add_theme_constant_override("separation", 16)

	# 1. Member Lookup Selector (Dynamic Type-Ahead Search of Center Members from any role)
	var lbl_member = Label.new(); lbl_member.text = "Center Member (Lookup / Search):"; lbl_member.add_theme_font_size_override("font_size", 13)
	mvbox.add_child(lbl_member)

	var search_hbox = HBoxContainer.new(); search_hbox.add_theme_constant_override("separation", 8)
	var e_search = LineEdit.new(); e_search.placeholder_text = "Type name to search center members..."; e_search.size_flags_horizontal = SIZE_EXPAND_FILL; e_search.custom_minimum_size = Vector2(0, 36)
	search_hbox.add_child(e_search)

	var opt_person = OptionButton.new(); opt_person.size_flags_horizontal = SIZE_EXPAND_FILL; opt_person.custom_minimum_size = Vector2(0, 36)
	var all_members = _get_all_center_members()

	var populate_person_dropdown = func(filter_text: String):
		opt_person.clear()
		var filter_lower = filter_text.strip_edges().to_lower()
		var count = 0
		for p in all_members:
			var fn = str(p.get("first_name", ""))
			var ln = str(p.get("last_name", ""))
			var role = str(p.get("primary_role", "Staff"))
			var full_name = (fn + " " + ln).strip_edges()
			if filter_lower == "" or full_name.to_lower().contains(filter_lower) or role.to_lower().contains(filter_lower):
				opt_person.add_item(full_name + " (" + role + ")", count)
				opt_person.set_item_metadata(count, {"name": full_name, "role": role})
				count += 1
		if count == 0:
			opt_person.add_item("No matching members found", 0)

	populate_person_dropdown.call("")
	e_search.text_changed.connect(func(new_text): populate_person_dropdown.call(new_text))

	if is_edit_mode:
		var cur_name = str(existing_shift_data.get("person_name", ""))
		e_search.text = cur_name
		populate_person_dropdown.call(cur_name)

	mvbox.add_child(search_hbox)
	mvbox.add_child(opt_person)

	# 2. Staff Classification Selector
	var lbl_role = Label.new(); lbl_role.text = "Staff Classification:"; lbl_role.add_theme_font_size_override("font_size", 13)
	mvbox.add_child(lbl_role)

	var role_hbox = HBoxContainer.new(); role_hbox.add_theme_constant_override("separation", 8)
	var opt_role = OptionButton.new(); opt_role.size_flags_horizontal = SIZE_EXPAND_FILL; opt_role.custom_minimum_size = Vector2(0, 36)

	var populate_roles = func():
		opt_role.clear()
		for i in range(available_roles.size()):
			opt_role.add_item(available_roles[i], i)

	populate_roles.call()

	var btn_manage_roles = Button.new(); btn_manage_roles.text = "⚙️ Manage Roles"; btn_manage_roles.custom_minimum_size = Vector2(130, 36)
	_style_outline_button(btn_manage_roles)
	btn_manage_roles.disabled = true
	btn_manage_roles.tooltip_text = "Staff Classifications are standardized (Volunteer, Intern, Staff, Team Leader)"

	role_hbox.add_child(opt_role)
	role_hbox.add_child(btn_manage_roles)
	mvbox.add_child(role_hbox)

	if is_edit_mode:
		var cur_role = str(existing_shift_data.get("shift_role", ""))
		if cur_role.contains("Supervisor") or cur_role == "Shift Supervisor": cur_role = "Team Leader"
		if not cur_role in available_roles: available_roles.append(cur_role); populate_roles.call()
		for i in range(available_roles.size()):
			if available_roles[i] == cur_role: opt_role.select(i); break

	# 3. Standardized Date Selector
	var lbl_date = Label.new(); lbl_date.text = "Shift Date (MM/DD/YYYY):"; lbl_date.add_theme_font_size_override("font_size", 13)
	mvbox.add_child(lbl_date)

	var date_hbox = HBoxContainer.new(); date_hbox.add_theme_constant_override("separation", 8)
	var e_date = LineEdit.new(); e_date.custom_minimum_size = Vector2(160, 36)
	var default_date = str(existing_shift_data.get("shift_date", Time.get_date_string_from_system())) if is_edit_mode else Time.get_date_string_from_system()
	e_date.text = default_date
	date_hbox.add_child(e_date)

	var lbl_weekday_indicator = Label.new()
	lbl_weekday_indicator.text = "(" + get_weekday_name_for_date_string(default_date) + ")"
	lbl_weekday_indicator.add_theme_font_size_override("font_size", 13)
	lbl_weekday_indicator.add_theme_color_override("font_color", Color(0.88, 0.35, 0.21, 1.0))
	date_hbox.add_child(lbl_weekday_indicator)

	e_date.text_changed.connect(func(new_val):
		lbl_weekday_indicator.text = "(" + get_weekday_name_for_date_string(new_val) + ")"
	)

	var btn_today = Button.new(); btn_today.text = "📅 Today"; btn_today.custom_minimum_size = Vector2(85, 36)
	_style_outline_button(btn_today)
	btn_today.pressed.connect(func():
		var today_s = Time.get_date_string_from_system()
		e_date.text = today_s
		lbl_weekday_indicator.text = "(" + get_weekday_name_for_date_string(today_s) + ")"
	)
	date_hbox.add_child(btn_today)
	mvbox.add_child(date_hbox)

	# 4. Standardized Start & Stop Time Selectors
	var time_hbox = HBoxContainer.new(); time_hbox.add_theme_constant_override("separation", 16)

	var start_vbox = VBoxContainer.new(); start_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	var lbl_start = Label.new(); lbl_start.text = "Start Time:"; lbl_start.add_theme_font_size_override("font_size", 13)
	start_vbox.add_child(lbl_start)

	var opt_start = OptionButton.new(); opt_start.custom_minimum_size = Vector2(0, 36)
	for t in STANDARD_TIME_SLOTS: opt_start.add_item(t)
	start_vbox.add_child(opt_start)
	time_hbox.add_child(start_vbox)

	var end_vbox = VBoxContainer.new(); end_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	var lbl_end = Label.new(); lbl_end.text = "End Time:"; lbl_end.add_theme_font_size_override("font_size", 13)
	end_vbox.add_child(lbl_end)

	var opt_end = OptionButton.new(); opt_end.custom_minimum_size = Vector2(0, 36)
	for t in STANDARD_TIME_SLOTS: opt_end.add_item(t)
	end_vbox.add_child(opt_end)
	time_hbox.add_child(end_vbox)

	if is_edit_mode:
		var cur_start = str(existing_shift_data.get("start_time", "03:00 PM"))
		var cur_end = str(existing_shift_data.get("end_time", "08:00 PM"))
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == cur_start: opt_start.select(i)
			if STANDARD_TIME_SLOTS[i] == cur_end: opt_end.select(i)
	else:
		opt_start.select(18) # 03:00 PM
		opt_end.select(28)   # 08:00 PM

	mvbox.add_child(time_hbox)

	# 5. Center or Area Selector (Default to Study Center & Disable Selection)
	var lbl_area = Label.new(); lbl_area.text = "Center or Area:"; lbl_area.add_theme_font_size_override("font_size", 13)
	mvbox.add_child(lbl_area)

	var area_hbox = HBoxContainer.new(); area_hbox.add_theme_constant_override("separation", 8)
	var opt_area = OptionButton.new(); opt_area.size_flags_horizontal = SIZE_EXPAND_FILL; opt_area.custom_minimum_size = Vector2(0, 36)

	var populate_areas = func():
		opt_area.clear()
		for i in range(available_areas.size()):
			opt_area.add_item(available_areas[i], i)

	populate_areas.call()
	opt_area.select(0) # Default = "Study Center"
	opt_area.disabled = true
	opt_area.tooltip_text = "Area selection disabled — defaulting to Study Center"

	var btn_manage_areas = Button.new(); btn_manage_areas.text = "⚙️ Manage Areas"; btn_manage_areas.custom_minimum_size = Vector2(130, 36)
	_style_outline_button(btn_manage_areas)
	btn_manage_areas.disabled = true
	btn_manage_areas.tooltip_text = "Area scheduling will be enabled in a future release"
	btn_manage_areas.pressed.connect(func():
		open_list_manager_modal("Area", available_areas, populate_areas)
	)

	area_hbox.add_child(opt_area)
	area_hbox.add_child(btn_manage_areas)
	mvbox.add_child(area_hbox)

	if is_edit_mode:
		var cur_area = str(existing_shift_data.get("area", "Study Center"))
		if not cur_area in available_areas: available_areas.append(cur_area); populate_areas.call()
		for i in range(available_areas.size()):
			if available_areas[i] == cur_area: opt_area.select(i); break

	# Bottom Action Buttons
	var btn_spacer = Control.new(); btn_spacer.custom_minimum_size = Vector2(0, 10)
	mvbox.add_child(btn_spacer)

	var btn_hbox = HBoxContainer.new(); btn_hbox.add_theme_constant_override("separation", 14)

	if is_edit_mode:
		var btn_modal_delete = Button.new()
		btn_modal_delete.text = "🗑️ Delete Shift"
		btn_modal_delete.custom_minimum_size = Vector2(130, 38)
		var d_st = StyleBoxFlat.new()
		d_st.bg_color = Color(1.0, 0.95, 0.95, 1.0)
		d_st.border_width_left = 1; d_st.border_width_top = 1; d_st.border_width_right = 1; d_st.border_width_bottom = 1
		d_st.border_color = Color(0.85, 0.30, 0.20, 0.8)
		d_st.corner_radius_top_left = 8; d_st.corner_radius_top_right = 8; d_st.corner_radius_bottom_left = 8; d_st.corner_radius_bottom_right = 8
		btn_modal_delete.add_theme_stylebox_override("normal", d_st)
		btn_modal_delete.add_theme_color_override("font_color", Color(0.85, 0.30, 0.20, 1.0))
		btn_modal_delete.pressed.connect(func():
			dialog.queue_free()
			_prompt_delete_shift_dialog(existing_shift_data)
		)
		btn_hbox.add_child(btn_modal_delete)

	var spacer = Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_hbox.add_child(spacer)

	var btn_cancel = Button.new(); btn_cancel.text = "Cancel"; btn_cancel.custom_minimum_size = Vector2(100, 38)
	_style_outline_button(btn_cancel)
	btn_cancel.pressed.connect(func(): dialog.queue_free())
	btn_hbox.add_child(btn_cancel)

	var btn_save = Button.new(); btn_save.text = "💾 Save Shift"; btn_save.custom_minimum_size = Vector2(140, 38)
	var s_st = StyleBoxFlat.new(); s_st.bg_color = Color(0.88, 0.35, 0.21, 1.0); s_st.corner_radius_top_left = 8; s_st.corner_radius_top_right = 8; s_st.corner_radius_bottom_left = 8; s_st.corner_radius_bottom_right = 8
	btn_save.add_theme_stylebox_override("normal", s_st)
	btn_save.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_save.pressed.connect(func():
		var sel_idx = opt_person.selected
		var person_meta = opt_person.get_item_metadata(sel_idx) if sel_idx >= 0 else null
		var p_name = person_meta["name"] if person_meta else e_search.text.strip_edges()
		if p_name == "": p_name = "John Smith"

		var s_role = opt_role.get_item_text(opt_role.selected)
		var s_date = e_date.text.strip_edges()
		if s_date == "": s_date = Time.get_date_string_from_system()

		var s_start = opt_start.get_item_text(opt_start.selected)
		var s_end = opt_end.get_item_text(opt_end.selected)
		var s_area = opt_area.get_item_text(opt_area.selected)

		if is_edit_mode:
			var u_val = str(existing_shift_data.get("entry_uuid"))
			sch_service.update_shift_entry_atomic(u_val, p_name, s_role, s_date, s_start, s_end, s_area, "Updated via modal")
		else:
			sch_service.create_shift_entry_atomic(p_name, s_role, s_date, s_start, s_end, s_area, "Created via modal")

		dialog.queue_free()
		call_deferred("_refresh_tab_content")
	)
	btn_hbox.add_child(btn_save)

	mvbox.add_child(btn_hbox)
	margin.add_child(mvbox)
	dialog.add_child(margin)

	add_child(dialog)
	dialog.popup_centered()

# Helper styling for modern rounded pills and outlines
func _style_pill_button(btn: Button, is_active: bool) -> void:
	var st = StyleBoxFlat.new()
	st.corner_radius_top_left = 18; st.corner_radius_top_right = 18; st.corner_radius_bottom_left = 18; st.corner_radius_bottom_right = 18
	st.content_margin_left = 14; st.content_margin_top = 6; st.content_margin_right = 14; st.content_margin_bottom = 6
	if is_active:
		st.bg_color = Color(0.25, 0.70, 0.85, 1.0)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
		st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
		st.border_color = Color(0.85, 0.88, 0.92, 1.0)
		btn.add_theme_color_override("font_color", Color(0.30, 0.38, 0.48, 1.0))
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", st)
	btn.add_theme_stylebox_override("pressed", st)

func _style_outline_button(btn: Button) -> void:
	var st = StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 1)
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
	st.border_color = Color(0.85, 0.88, 0.92, 1.0)
	st.corner_radius_top_left = 14; st.corner_radius_top_right = 14; st.corner_radius_bottom_left = 14; st.corner_radius_bottom_right = 14
	st.content_margin_left = 12; st.content_margin_top = 6; st.content_margin_right = 12; st.content_margin_bottom = 6
	btn.add_theme_color_override("font_color", Color(0.28, 0.34, 0.42, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.88, 0.35, 0.21, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.15, 0.22, 0.32, 1.0))
	btn.add_theme_color_override("font_focus_color", Color(0.28, 0.34, 0.42, 1.0))
	btn.add_theme_stylebox_override("normal", st)

	var hst = st.duplicate() as StyleBoxFlat
	hst.bg_color = Color(0.94, 0.97, 1.0, 1.0)
	hst.border_color = Color(0.88, 0.35, 0.21, 0.8)
	btn.add_theme_stylebox_override("hover", hst)
	btn.add_theme_stylebox_override("pressed", hst)

func _style_primary_button(btn: Button) -> void:
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.88, 0.35, 0.21, 1.0)
	st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
	st.content_margin_left = 12; st.content_margin_top = 6; st.content_margin_right = 12; st.content_margin_bottom = 6
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_stylebox_override("normal", st)

	var hst = st.duplicate() as StyleBoxFlat
	hst.bg_color = Color(0.78, 0.28, 0.15, 1.0)
	btn.add_theme_stylebox_override("hover", hst)
	btn.add_theme_stylebox_override("pressed", hst)

	# Clean disabled styling matching other outline buttons
	var dst = st.duplicate() as StyleBoxFlat
	dst.bg_color = Color(0.98, 0.98, 0.98, 0.6)
	dst.border_color = Color(0.90, 0.92, 0.95, 0.6)
	btn.add_theme_stylebox_override("disabled", dst)
	btn.add_theme_color_override("font_disabled_color", Color(0.65, 0.72, 0.80, 1.0))

func _style_checkbox(chk: CheckBox) -> void:
	chk.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
	chk.add_theme_color_override("font_pressed_color", Color(0.08, 0.12, 0.20, 1.0))
	chk.add_theme_color_override("font_hover_color", Color(0.88, 0.35, 0.21, 1.0))
	chk.add_theme_color_override("font_hover_pressed_color", Color(0.88, 0.35, 0.21, 1.0))
	chk.add_theme_color_override("font_focus_color", Color(0.12, 0.18, 0.26, 1.0))
	chk.add_theme_color_override("font_disabled_color", Color(0.55, 0.62, 0.70, 1.0))

# ==================== CLIPBOARD & SELECTION ENGINE ====================

func _get_all_ordered_shifts() -> Array:
	if not sch_service: return []
	var start_d = get_date_string_for_day_index(0)
	var end_d = get_date_string_for_day_index(6)
	var shifts = sch_service.get_shift_entries_for_range(start_d, end_d)

	for s in shifts:
		var s_date = str(s.get("shift_date", ""))
		s["_computed_day_idx"] = get_day_index_from_date_string(s_date)

	shifts.sort_custom(func(a, b):
		if a["_computed_day_idx"] != b["_computed_day_idx"]:
			return a["_computed_day_idx"] < b["_computed_day_idx"]
		var sort_a = int(a.get("sort_order", 0))
		var sort_b = int(b.get("sort_order", 0))
		if sort_a != sort_b:
			return sort_a < sort_b
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return shifts

func select_shift_by_id(target_uuid: String, is_shift_pressed: bool, is_cmd_pressed: bool) -> void:
	var ordered = _get_all_ordered_shifts()
	var target_exists = false
	for s in ordered:
		if str(s.get("entry_uuid")) == target_uuid:
			target_exists = true
			break
	if not target_exists: return

	if is_shift_pressed and selection_anchor_id != "":
		var anchor_idx = -1
		var target_idx = -1
		for i in range(ordered.size()):
			var u = str(ordered[i].get("entry_uuid"))
			if u == selection_anchor_id: anchor_idx = i
			if u == target_uuid: target_idx = i

		if anchor_idx != -1 and target_idx != -1:
			var min_i = min(anchor_idx, target_idx)
			var max_i = max(anchor_idx, target_idx)
			selected_shift_ids.clear()
			for i in range(min_i, max_i + 1):
				selected_shift_ids[str(ordered[i].get("entry_uuid"))] = true
		else:
			selected_shift_ids = {target_uuid: true}
			selection_anchor_id = target_uuid
	else:
		if selected_shift_ids.has(target_uuid):
			selected_shift_ids.erase(target_uuid)
		else:
			selected_shift_ids[target_uuid] = true
			selection_anchor_id = target_uuid

	call_deferred("_refresh_tab_content")

func _copy_selected_shifts() -> void:
	if not sch_service or selected_shift_ids.size() == 0: return

	var ordered = _get_all_ordered_shifts()
	var snapshot_shifts = []
	var min_day_idx = 7

	for s in ordered:
		var u = str(s.get("entry_uuid"))
		if u in selected_shift_ids:
			snapshot_shifts.append(s.duplicate())
			var day_idx = int(s["_computed_day_idx"])
			if day_idx < min_day_idx:
				min_day_idx = day_idx

	if min_day_idx == 7: min_day_idx = 0

	clipboard = {
		"mode": "copy",
		"source_shift_ids": selected_shift_ids.keys(),
		"shifts": snapshot_shifts,
		"anchor_day_index": min_day_idx
	}
	print("Copied ", snapshot_shifts.size(), " selected shift(s) to clipboard.")
	call_deferred("_refresh_tab_content")

func _cut_selected_shifts() -> void:
	if not sch_service or selected_shift_ids.size() == 0: return

	var ordered = _get_all_ordered_shifts()
	var snapshot_shifts = []
	var min_day_idx = 7

	for s in ordered:
		var u = str(s.get("entry_uuid"))
		if u in selected_shift_ids:
			snapshot_shifts.append(s.duplicate())
			var day_idx = int(s["_computed_day_idx"])
			if day_idx < min_day_idx:
				min_day_idx = day_idx

	if min_day_idx == 7: min_day_idx = 0

	clipboard = {
		"mode": "cut",
		"source_shift_ids": selected_shift_ids.keys(),
		"shifts": snapshot_shifts,
		"anchor_day_index": min_day_idx
	}
	print("Cut ", snapshot_shifts.size(), " selected shift(s) to clipboard.")
	call_deferred("_refresh_tab_content")

func _paste_clipboard_shifts() -> void:
	if clipboard.size() == 0 or not sch_service: return
	if paste_target_day_index < 0: return

	var mode = str(clipboard.get("mode", "copy"))
	var snapshot = clipboard.get("shifts", [])
	var anchor_day_idx = int(clipboard.get("anchor_day_index", 0))

	var moves = []
	var new_records = []

	for s in snapshot:
		var orig_day_idx = int(s.get("_computed_day_idx", 0))
		var offset = orig_day_idx - anchor_day_idx
		var dest_day_idx = paste_target_day_index + offset

		if dest_day_idx > 6:
			printerr("Cannot paste: some shifts would fall beyond Sunday. No shifts were pasted.")
			return

		var dest_day_code = DAYS_META[dest_day_idx]["code"]
		var dest_date_s = get_date_string_for_day_index(dest_day_idx)

		if mode == "cut":
			moves.append({
				"entry_uuid": str(s.get("entry_uuid")),
				"target_date": dest_date_s
			})
		else:
			new_records.append({
				"person_name": str(s.get("person_name")),
				"shift_role": str(s.get("shift_role")),
				"shift_date": dest_date_s,
				"start_time": str(s.get("start_time")),
				"end_time": str(s.get("end_time")),
				"area": str(s.get("area")),
				"notes": str(s.get("notes", "")) + " (Pasted into " + dest_day_code + ")"
			})

	if mode == "cut":
		var res = sch_service.cut_paste_shifts_atomic(moves)
		if res["success"]:
			print("Atomic Cut/Paste completed successfully.")
			clipboard.clear()
	else:
		var res = sch_service.copy_paste_shifts_atomic(new_records)
		if res["success"]:
			print("Atomic Copy/Paste completed successfully.")

	selected_shift_ids.clear()
	call_deferred("_refresh_tab_content")

func _delete_selected_shifts() -> void:
	if not sch_service or selected_shift_ids.size() == 0: return

	var uuids_to_del = selected_shift_ids.keys()
	var res = sch_service.delete_shifts_by_uuids_atomic(uuids_to_del)
	if res["success"]:
		print("Deleted ", uuids_to_del.size(), " selected shift record(s).")
		selected_shift_ids.clear()
		selection_anchor_id = ""
		call_deferred("_refresh_tab_content")

func _prompt_delete_shift_dialog(shift_data: Dictionary) -> void:
	var confirm = ConfirmationDialog.new()
	confirm.title = "🗑️ Delete Shift"
	confirm.dialog_text = "Are you sure you want to delete this shift entry for " + str(shift_data.get("person_name", "this member")) + "?"
	confirm.confirmed.connect(func():
		var s_uuid = str(shift_data.get("entry_uuid"))
		sch_service.delete_shifts_by_uuids_atomic([s_uuid])
		call_deferred("_refresh_tab_content")
	)
	add_child(confirm)
	confirm.popup_centered()

func open_list_manager_modal(type_title: String, list_ref: Array, on_update_cb: Callable) -> void:
	var dialog = Window.new()
	dialog.title = "⚙️ Manage " + type_title + " Options"
	dialog.size = Vector2i(520, 500)
	dialog.exclusive = true
	dialog.transient = true
	dialog.close_requested.connect(func(): dialog.queue_free())

	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)

	var mvbox = VBoxContainer.new(); mvbox.add_theme_constant_override("separation", 12)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	var items_vbox = VBoxContainer.new()
	items_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(items_vbox)
	mvbox.add_child(scroll)

	var populate_items: Callable
	populate_items = func():
		for child in items_vbox.get_children():
			child.queue_free()
		
		for i in range(list_ref.size()):
			var idx = i
			var val = list_ref[i]

			var row_hbox = HBoxContainer.new()
			row_hbox.add_theme_constant_override("separation", 10)

			var lbl = Label.new()
			lbl.text = val
			lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 13)
			row_hbox.add_child(lbl)

			var btn_rename = Button.new()
			btn_rename.text = "✏️ Rename"
			btn_rename.custom_minimum_size = Vector2(95, 30)
			_style_outline_button(btn_rename)
			btn_rename.pressed.connect(func():
				var prompt = Window.new()
				prompt.title = "Rename Option"
				prompt.size = Vector2i(400, 160)
				prompt.exclusive = true
				prompt.transient = true
				prompt.close_requested.connect(func(): prompt.queue_free())

				var pmargin = MarginContainer.new()
				pmargin.set_anchors_preset(PRESET_FULL_RECT)
				pmargin.add_theme_constant_override("margin_left", 16)
				pmargin.add_theme_constant_override("margin_top", 16)
				pmargin.add_theme_constant_override("margin_right", 16)
				pmargin.add_theme_constant_override("margin_bottom", 16)

				var pvbox = VBoxContainer.new()
				pvbox.add_theme_constant_override("separation", 10)

				var plbl = Label.new(); plbl.text = "Rename '" + val + "' to:"; plbl.add_theme_font_size_override("font_size", 13)
				pvbox.add_child(plbl)

				var pe_name = LineEdit.new(); pe_name.text = val; pe_name.custom_minimum_size = Vector2(0, 36)
				pvbox.add_child(pe_name)

				var pbtn_hbox = HBoxContainer.new(); pbtn_hbox.alignment = BoxContainer.ALIGNMENT_END; pbtn_hbox.add_theme_constant_override("separation", 10)
				var pbtn_cancel = Button.new(); pbtn_cancel.text = "Cancel"; _style_outline_button(pbtn_cancel); pbtn_cancel.pressed.connect(func(): prompt.queue_free())
				pbtn_hbox.add_child(pbtn_cancel)

				var pbtn_save = Button.new(); pbtn_save.text = "Save"; _style_outline_button(pbtn_save)
				pbtn_save.pressed.connect(func():
					var new_val = pe_name.text.strip_edges()
					if new_val != "":
						list_ref[idx] = new_val
						on_update_cb.call()
						prompt.queue_free()
						populate_items.call()
				)
				pbtn_hbox.add_child(pbtn_save)
				pvbox.add_child(pbtn_hbox)

				pmargin.add_child(pvbox)
				prompt.add_child(pmargin)
				dialog.add_child(prompt)
				prompt.popup_centered()
			)
			row_hbox.add_child(btn_rename)

			var btn_del = Button.new()
			btn_del.text = "🗑️ Delete"
			btn_del.custom_minimum_size = Vector2(95, 30)
			_style_outline_button(btn_del)
			btn_del.pressed.connect(func():
				var confirm = ConfirmationDialog.new()
				confirm.title = "⚠️ Warning: Delete Option?"
				confirm.dialog_text = "Are you sure you want to delete '" + val + "' from the " + type_title + " list?\nThis action cannot be undone."
				confirm.confirmed.connect(func():
					list_ref.remove_at(idx)
					on_update_cb.call()
					populate_items.call()
				)
				dialog.add_child(confirm)
				confirm.popup_centered()
			)
			row_hbox.add_child(btn_del)

			items_vbox.add_child(row_hbox)

	populate_items.call()

	var add_hbox = HBoxContainer.new()
	add_hbox.add_theme_constant_override("separation", 10)

	var e_new_name = LineEdit.new()
	e_new_name.placeholder_text = "Enter initial name for new " + type_title + "..."
	e_new_name.size_flags_horizontal = SIZE_EXPAND_FILL
	e_new_name.custom_minimum_size = Vector2(0, 36)
	add_hbox.add_child(e_new_name)

	var btn_add = Button.new()
	btn_add.text = "➕ Add New"
	btn_add.custom_minimum_size = Vector2(110, 36)
	var add_st = StyleBoxFlat.new()
	add_st.bg_color = _get_active_theme_color()
	add_st.corner_radius_top_left = 6; add_st.corner_radius_top_right = 6; add_st.corner_radius_bottom_left = 6; add_st.corner_radius_bottom_right = 6
	btn_add.add_theme_stylebox_override("normal", add_st)
	btn_add.add_theme_stylebox_override("hover", add_st)
	btn_add.add_theme_stylebox_override("pressed", add_st)
	btn_add.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn_add.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn_add.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn_add.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

	var handle_add_new = func():
		var name_val = e_new_name.text.strip_edges()
		if name_val != "":
			list_ref.append(name_val)
			on_update_cb.call()
			e_new_name.text = ""
			populate_items.call()

	btn_add.pressed.connect(handle_add_new)
	add_hbox.add_child(btn_add)
	mvbox.add_child(add_hbox)

	var sep = ColorRect.new(); sep.custom_minimum_size = Vector2(0, 1); sep.color = Color(0.88, 0.91, 0.95, 1.0)
	mvbox.add_child(sep)

	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.custom_minimum_size = Vector2(100, 36)
	_style_outline_button(btn_close)
	btn_close.pressed.connect(func(): dialog.queue_free())
	btn_close.size_flags_horizontal = SIZE_SHRINK_CENTER
	mvbox.add_child(btn_close)

	margin.add_child(mvbox)
	dialog.add_child(margin)
	add_child(dialog)
	dialog.popup_centered()

func _render_shift_cards(container: PanelContainer, hours_data: Dictionary) -> void:
	var main_st = StyleBoxFlat.new()
	main_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	main_st.corner_radius_top_left = 10; main_st.corner_radius_top_right = 10; main_st.corner_radius_bottom_left = 10; main_st.corner_radius_bottom_right = 10
	main_st.content_margin_left = 10; main_st.content_margin_top = 10; main_st.content_margin_right = 10; main_st.content_margin_bottom = 10
	container.add_theme_stylebox_override("panel", main_st)

	var scroll = ScrollContainer.new(); scroll.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.size_flags_vertical = SIZE_EXPAND_FILL
	var hbox = HBoxContainer.new(); hbox.size_flags_horizontal = SIZE_EXPAND_FILL; hbox.add_theme_constant_override("separation", 10)

	var shifts = _get_all_ordered_shifts()

	var cut_uuids = {}
	if clipboard.get("mode") == "cut":
		for u in clipboard.get("source_shift_ids", []):
			cut_uuids[str(u)] = true

	all_card_nodes.clear()
	all_day_columns.clear()

	for meta in DAYS_META:
		var d = meta["code"]
		var day_idx = meta["day_idx"]
		var is_target = (day_idx == paste_target_day_index)

		var day_column = DayColumnControl.new(d, day_idx, is_target, self)
		day_column.size_flags_horizontal = SIZE_EXPAND_FILL
		day_column.size_flags_vertical = SIZE_EXPAND_FILL
		day_column.custom_minimum_size = Vector2(0, 300)
		all_day_columns.append(day_column)

		var cvbox = VBoxContainer.new(); cvbox.add_theme_constant_override("separation", 6)

		var date_s = get_date_string_for_day_index(day_idx)

		var btn_header = Button.new()
		btn_header.text = ("🎯 " if is_target else "📅 ") + d + " (" + _format_short_date(date_s) + ")"
		btn_header.custom_minimum_size = Vector2(0, 32)
		var h_st = StyleBoxFlat.new()
		h_st.bg_color = Color(0.88, 0.35, 0.21, 0.15) if is_target else Color(0.94, 0.96, 0.98, 1.0)
		h_st.border_width_left = 2 if is_target else 0; h_st.border_width_top = 2 if is_target else 0; h_st.border_width_right = 2 if is_target else 0; h_st.border_width_bottom = 2 if is_target else 0
		h_st.border_color = Color(0.88, 0.35, 0.21, 1.0)
		h_st.corner_radius_top_left = 6; h_st.corner_radius_top_right = 6; h_st.corner_radius_bottom_left = 6; h_st.corner_radius_bottom_right = 6
		btn_header.add_theme_stylebox_override("normal", h_st)
		btn_header.add_theme_color_override("font_color", Color(0.88, 0.35, 0.21, 1.0) if is_target else Color(0.12, 0.16, 0.22, 1.0))
		btn_header.pressed.connect(func():
			if paste_target_day_index == day_idx:
				paste_target_day_index = -1
			else:
				paste_target_day_index = day_idx
			call_deferred("_refresh_tab_content")
		)
		btn_header.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:
				if ev.button_index == MOUSE_BUTTON_RIGHT or ev.double_click:
					open_hours_override_modal(meta["name"], date_s)
		)
		btn_header.add_theme_font_size_override("font_size", 15)
		cvbox.add_child(btn_header)

		# Make hours each day highly legible, checking overrides first!
		var full_day_name = meta["name"]
		var override = get_hour_override_for_date(date_s)
		var is_override_active = (override.size() > 0)

		var h_lbl = Label.new()
		h_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		h_lbl.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				open_hours_override_modal(full_day_name, date_s)
		)
		if is_override_active:
			var ov_closed = int(override.get("is_closed", 0)) == 1
			if ov_closed:
				h_lbl.text = "🔴 Closed (Override)"
				h_lbl.add_theme_color_override("font_color", Color(0.85, 0.30, 0.20, 1.0))
			else:
				var s1_start = str(override.get("session1_start", "03:00 PM"))
				var s1_end = str(override.get("session1_end", "08:00 PM"))
				var has_split = int(override.get("has_split_shift", 0)) == 1
				if has_split:
					var s2_start = str(override.get("session2_start", "05:00 PM"))
					var s2_end = str(override.get("session2_end", "08:00 PM"))
					h_lbl.text = "🕒 " + s1_start + "-" + s1_end + " & " + s2_start + "-" + s2_end
				else:
					h_lbl.text = "🕒 " + s1_start + " - " + s1_end
				h_lbl.add_theme_color_override("font_color", Color(0.88, 0.35, 0.21, 1.0)) # Terracotta highlight for overrides!
		else:
			var day_hours = hours_data.get(full_day_name, {"open_time": "09:00 AM", "close_time": "06:00 PM", "is_closed": 0})
			var day_is_closed = int(day_hours.get("is_closed", 0)) == 1
			var open_str = str(day_hours.get("open_time", "03:00 PM"))
			var close_str = str(day_hours.get("close_time", "08:00 PM"))

			if day_is_closed:
				h_lbl.text = "🔴 Closed"
				h_lbl.add_theme_color_override("font_color", Color(0.85, 0.30, 0.20, 1.0))
			else:
				h_lbl.text = "🕒 " + open_str + " - " + close_str
				h_lbl.add_theme_color_override("font_color", Color(0.12, 0.45, 0.22, 1.0)) # Rich high-contrast forest green!

		h_lbl.add_theme_font_size_override("font_size", 14)
		cvbox.add_child(h_lbl)

		for s in shifts:
			var s_uuid = str(s.get("entry_uuid"))
			var s_date = str(s.get("shift_date", ""))
			var s_day_idx = get_day_index_from_date_string(s_date)
			if s_day_idx != day_idx: continue

			var is_sel = selected_shift_ids.has(s_uuid)
			var is_pending_cut = cut_uuids.has(s_uuid)

			var item_card = ShiftCardControl.new(s, is_sel, is_pending_cut, self)
			cvbox.add_child(item_card)
			all_card_nodes.append(item_card)

		day_column.add_child(cvbox)
		hbox.add_child(day_column)

	scroll.add_child(hbox)
	container.add_child(scroll)

# ==================== TABLE VIEW RENDERER ====================

func _render_shift_table(container: PanelContainer) -> void:
	var scroll = ScrollContainer.new(); scroll.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.size_flags_vertical = SIZE_EXPAND_FILL
	var tbl_card = PanelContainer.new(); tbl_card.size_flags_horizontal = SIZE_EXPAND_FILL; tbl_card.size_flags_vertical = SIZE_EXPAND_FILL

	var tst = StyleBoxFlat.new()
	tst.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	tst.border_width_left = 1; tst.border_width_top = 1; tst.border_width_right = 1; tst.border_width_bottom = 1
	tst.border_color = Color(0.88, 0.91, 0.95, 1.0)
	tst.corner_radius_top_left = 10; tst.corner_radius_top_right = 10; tst.corner_radius_bottom_left = 10; tst.corner_radius_bottom_right = 10
	tbl_card.add_theme_stylebox_override("panel", tst)

	var tvbox = VBoxContainer.new(); tvbox.size_flags_horizontal = SIZE_EXPAND_FILL; tvbox.add_theme_constant_override("separation", 0)

	var th_panel = PanelContainer.new()
	var th_st = StyleBoxFlat.new()
	th_st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
	th_st.content_margin_left = 18; th_st.content_margin_top = 12; th_st.content_margin_right = 18; th_st.content_margin_bottom = 12
	th_panel.add_theme_stylebox_override("panel", th_st)

	var th_hbox = HBoxContainer.new()
	var h_date = Label.new(); h_date.text = "Date"; h_date.custom_minimum_size = Vector2(160, 0)
	h_date.add_theme_font_size_override("font_size", 13); h_date.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 1.0))
	th_hbox.add_child(h_date)

	var h_hours = Label.new(); h_hours.text = "Hours"; h_hours.custom_minimum_size = Vector2(180, 0)
	h_hours.add_theme_font_size_override("font_size", 13); h_hours.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 1.0))
	th_hbox.add_child(h_hours)

	var h_staff = Label.new(); h_staff.text = "Staff & Role"; h_staff.size_flags_horizontal = SIZE_EXPAND_FILL
	h_staff.add_theme_font_size_override("font_size", 13); h_staff.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 1.0))
	th_hbox.add_child(h_staff)

	th_panel.add_child(th_hbox)
	tvbox.add_child(th_panel)

	var sep1 = ColorRect.new(); sep1.custom_minimum_size = Vector2(0, 1); sep1.color = Color(0.88, 0.91, 0.95, 1.0)
	tvbox.add_child(sep1)

	var shifts = _get_all_ordered_shifts()
	if shifts.size() > 0:
		for i in range(shifts.size()):
			var s = shifts[i]
			var s_uuid = str(s.get("entry_uuid"))
			var name = str(s.get("person_name", ""))
			var role = str(s.get("shift_role", ""))
			var date_str = str(s.get("shift_date", ""))
			var start_t = str(s.get("start_time", "03:00 PM"))
			var end_t = str(s.get("end_time", "08:00 PM"))
			var area = str(s.get("area", ""))

			var day_idx = get_day_index_from_date_string(date_str)
			var day_name = DAYS_META[day_idx]["code"]

			var formatted_date = day_name + ", " + date_str

			var row_panel = PanelContainer.new()
			row_panel.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed:
					if ev.button_index == MOUSE_BUTTON_LEFT:
						open_shift_modal(s)
					elif ev.button_index == MOUSE_BUTTON_RIGHT:
						_prompt_delete_shift_dialog(s)
			)

			var r_st = StyleBoxFlat.new()
			r_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
			r_st.content_margin_left = 18; r_st.content_margin_top = 12; r_st.content_margin_right = 18; r_st.content_margin_bottom = 12
			row_panel.add_theme_stylebox_override("panel", r_st)

			var r_hbox = HBoxContainer.new()

			var l_date = Label.new(); l_date.text = formatted_date; l_date.custom_minimum_size = Vector2(160, 0)
			l_date.add_theme_font_size_override("font_size", 13); l_date.add_theme_color_override("font_color", Color(0.18, 0.24, 0.32, 1.0))
			r_hbox.add_child(l_date)

			var l_hours = Label.new(); l_hours.text = start_t + " - " + end_t; l_hours.custom_minimum_size = Vector2(180, 0)
			l_hours.add_theme_font_size_override("font_size", 13); l_hours.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 1.0))
			r_hbox.add_child(l_hours)

			var l_staff = Label.new(); l_staff.text = "👤 " + name + " (" + role + ") • " + area; l_staff.size_flags_horizontal = SIZE_EXPAND_FILL
			l_staff.add_theme_font_size_override("font_size", 13); l_staff.add_theme_color_override("font_color", Color(0.18, 0.24, 0.32, 1.0))
			r_hbox.add_child(l_staff)

			row_panel.add_child(r_hbox)
			tvbox.add_child(row_panel)

			if i < shifts.size() - 1:
				var r_sep = ColorRect.new(); r_sep.custom_minimum_size = Vector2(0, 1); r_sep.color = Color(0.93, 0.95, 0.97, 1.0)
				tvbox.add_child(r_sep)
	else:
		var empty_panel = PanelContainer.new()
		var ep_st = StyleBoxFlat.new(); ep_st.content_margin_left = 18; ep_st.content_margin_top = 20; ep_st.content_margin_right = 18; ep_st.content_margin_bottom = 20
		empty_panel.add_theme_stylebox_override("panel", ep_st)
		var empty = Label.new(); empty.text = "No staff shifts scheduled."; empty.add_theme_font_size_override("font_size", 13); empty.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		empty_panel.add_child(empty)
		tvbox.add_child(empty_panel)

	tbl_card.add_child(tvbox)
	scroll.add_child(tbl_card)
	container.add_child(scroll)

func _style_circle_action_button(btn: Button) -> void:
	var st = StyleBoxFlat.new()
	st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
	st.border_color = Color(0.85, 0.88, 0.92, 1.0)
	st.corner_radius_top_left = 16; st.corner_radius_top_right = 16; st.corner_radius_bottom_left = 16; st.corner_radius_bottom_right = 16
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", st)
	btn.add_theme_stylebox_override("pressed", st)

# ==================== TAB 2 & TAB 3 RENDERERS ====================

# ==================== REUSABLE PHASE 3 SESSION CREATE / EDIT FORM DIALOG ====================

# ==================== REUSABLE PHASE 3 SESSION CREATE / EDIT FORM DIALOG ====================

func open_session_editor_modal(session_data: Dictionary = {}) -> void:
	if not sch_service and db:
		sch_service = SchedulesServiceScript.new(db)
	if not config_service and db:
		config_service = SessionConfigServiceScript.new(db)

	var is_edit_mode = session_data.size() > 0 and session_data.has("id")
	var target_session_id = 0
	if is_edit_mode:
		target_session_id = int(session_data.get("id", 0))

	var dialog = Window.new()
	if is_edit_mode:
		dialog.title = "✏️ Edit Session: " + str(session_data.get("title", ""))
	else:
		dialog.title = "➕ Create New Session"
	dialog.size = Vector2i(840, 780)
	dialog.exclusive = true
	dialog.transient = true

	var modal_bg = PanelContainer.new()
	modal_bg.set_anchors_preset(PRESET_FULL_RECT)
	var modal_style = StyleBoxFlat.new()
	modal_style.bg_color = Color(0.98, 0.99, 1.0, 1.0) # Warm crisp light background
	modal_style.corner_radius_top_left = 8; modal_style.corner_radius_top_right = 8
	modal_style.corner_radius_bottom_left = 8; modal_style.corner_radius_bottom_right = 8
	modal_bg.add_theme_stylebox_override("panel", modal_style)
	dialog.add_child(modal_bg)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28); margin.add_theme_constant_override("margin_top", 24); margin.add_theme_constant_override("margin_right", 28); margin.add_theme_constant_override("margin_bottom", 24)
	modal_bg.add_child(margin)

	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var mvbox = VBoxContainer.new(); mvbox.size_flags_horizontal = SIZE_EXPAND_FILL; mvbox.add_theme_constant_override("separation", 16)

	# Status / Error Alert Banner
	var err_banner = Label.new()
	err_banner.add_theme_font_size_override("font_size", 14)
	err_banner.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0))
	err_banner.visible = false
	mvbox.add_child(err_banner)

	# Helper to create uniform card containers
	var _create_group_card = func() -> PanelContainer:
		var card = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.95, 0.96, 0.98, 1.0) # Light tint card
		card_style.corner_radius_top_left = 8; card_style.corner_radius_top_right = 8
		card_style.corner_radius_bottom_left = 8; card_style.corner_radius_bottom_right = 8
		card_style.content_margin_left = 16; card_style.content_margin_right = 16
		card_style.content_margin_top = 14; card_style.content_margin_bottom = 14
		card.add_theme_stylebox_override("panel", card_style)
		return card

	var _clean_str = func(v, fallback = "") -> String:
		if v == null or str(v) == "<null>": return fallback
		return str(v)

	# ---------------- GROUP 1: SESSION DETAILS ----------------
	var g1_lbl = Label.new(); g1_lbl.text = "1. Session Details"; g1_lbl.add_theme_font_size_override("font_size", 16); g1_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	mvbox.add_child(g1_lbl)

	var g1_card = _create_group_card.call()
	var g1_vbox = VBoxContainer.new(); g1_vbox.add_theme_constant_override("separation", 10)

	# Session Type Picker
	var lbl_type = Label.new(); lbl_type.text = "Session Type *"
	lbl_type.add_theme_font_size_override("font_size", 14); lbl_type.add_theme_color_override("font_color", Color(0.20, 0.26, 0.34, 1.0))
	g1_vbox.add_child(lbl_type)

	var opt_type = OptionButton.new(); opt_type.custom_minimum_size = Vector2(0, 40)
	var all_types = []
	if config_service:
		all_types = config_service.get_all_session_types(true)

	var selected_type_id = int(session_data.get("session_type_id", 1))
	var type_id_map = []
	var selected_type_idx = 0

	for i in range(all_types.size()):
		var t = all_types[i]
		var t_id = int(t["id"])
		var t_name = str(t["name"])
		var t_active = int(t.get("is_active", 1)) == 1

		# Show active types, or assigned inactive type
		if t_active or t_id == selected_type_id:
			var display_text = t_name if t_active else t_name + " [Inactive]"
			opt_type.add_item(display_text)
			type_id_map.append(t_id)
			if t_id == selected_type_id:
				selected_type_idx = type_id_map.size() - 1

	if type_id_map.size() > 0: opt_type.select(selected_type_idx)
	g1_vbox.add_child(opt_type)

	# Session Title Input
	var lbl_title = Label.new(); lbl_title.text = "Session Title *"
	lbl_title.add_theme_font_size_override("font_size", 14); lbl_title.add_theme_color_override("font_color", Color(0.20, 0.26, 0.34, 1.0))
	g1_vbox.add_child(lbl_title)

	var input_title = LineEdit.new()
	input_title.placeholder_text = "e.g. Real Life Fellows - Introductory Week 1"
	input_title.text = _clean_str.call(session_data.get("title"), "")
	input_title.custom_minimum_size = Vector2(0, 40)
	g1_vbox.add_child(input_title)

	# Session Description Input
	var lbl_desc = Label.new(); lbl_desc.text = "Description (Optional)"
	lbl_desc.add_theme_font_size_override("font_size", 14); lbl_desc.add_theme_color_override("font_color", Color(0.20, 0.26, 0.34, 1.0))
	g1_vbox.add_child(lbl_desc)

	var input_desc = TextEdit.new()
	input_desc.placeholder_text = "Enter session overview, topics, or instructions..."
	input_desc.text = _clean_str.call(session_data.get("description"), "")
	input_desc.custom_minimum_size = Vector2(0, 70)
	g1_vbox.add_child(input_desc)

	g1_card.add_child(g1_vbox)
	mvbox.add_child(g1_card)

	# ---------------- GROUP 2: DATE AND TIME ----------------
	var g2_lbl = Label.new(); g2_lbl.text = "2. Date & Time"; g2_lbl.add_theme_font_size_override("font_size", 16); g2_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	mvbox.add_child(g2_lbl)

	var dt_card = _create_group_card.call()
	var dt_hbox = HBoxContainer.new(); dt_hbox.add_theme_constant_override("separation", 14)

	var date_vbox = VBoxContainer.new(); date_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	var lbl_date = Label.new(); lbl_date.text = "Date (MM/DD/YYYY) *"; lbl_date.add_theme_font_size_override("font_size", 13); lbl_date.add_theme_color_override("font_color", Color(0.20, 0.26, 0.34, 1.0))
	date_vbox.add_child(lbl_date)

	var date_input_hbox = HBoxContainer.new(); date_input_hbox.add_theme_constant_override("separation", 6)
	var raw_init_date = str(session_data.get("date_text", Time.get_date_string_from_system()))
	var input_date = LineEdit.new()
	if sch_service:
		input_date.text = sch_service.format_iso_to_display_date(raw_init_date)
	else:
		input_date.text = raw_init_date
	input_date.placeholder_text = "e.g. 07/24/2026 or 08221965"
	input_date.custom_minimum_size = Vector2(0, 40)
	input_date.size_flags_horizontal = SIZE_EXPAND_FILL

	var _fmt_date = func(t = ""):
		if sch_service:
			input_date.text = sch_service.format_iso_to_display_date(input_date.text)
	input_date.focus_exited.connect(_fmt_date)
	input_date.text_submitted.connect(_fmt_date)

	date_input_hbox.add_child(input_date)

	var btn_today = Button.new(); btn_today.text = "Today"; btn_today.custom_minimum_size = Vector2(64, 40)
	_style_outline_button(btn_today)
	btn_today.pressed.connect(func():
		var today_iso = Time.get_date_string_from_system()
		input_date.text = sch_service.format_iso_to_display_date(today_iso) if sch_service else today_iso
	)
	date_input_hbox.add_child(btn_today)

	var btn_tomorrow = Button.new(); btn_tomorrow.text = "+1 Day"; btn_tomorrow.custom_minimum_size = Vector2(64, 40)
	_style_outline_button(btn_tomorrow)
	btn_tomorrow.pressed.connect(func():
		var sys_time = Time.get_unix_time_from_system() + 86400
		var tom_dict = Time.get_datetime_dict_from_unix_time(sys_time)
		var tom_iso = "%04d-%02d-%02d" % [tom_dict["year"], tom_dict["month"], tom_dict["day"]]
		input_date.text = sch_service.format_iso_to_display_date(tom_iso) if sch_service else tom_iso
	)
	date_input_hbox.add_child(btn_tomorrow)

	date_vbox.add_child(date_input_hbox)
	dt_hbox.add_child(date_vbox)

	var start_vbox = VBoxContainer.new(); start_vbox.custom_minimum_size = Vector2(160, 0)
	var lbl_start = Label.new(); lbl_start.text = "Start Time *"; lbl_start.add_theme_font_size_override("font_size", 13); lbl_start.add_theme_color_override("font_color", Color(0.20, 0.26, 0.34, 1.0))
	start_vbox.add_child(lbl_start)
	var opt_start = OptionButton.new(); opt_start.custom_minimum_size = Vector2(0, 40)
	for t in STANDARD_TIME_SLOTS: opt_start.add_item(t)
	var cur_start = str(session_data.get("start_time", "09:00 AM"))
	for i in range(STANDARD_TIME_SLOTS.size()):
		if STANDARD_TIME_SLOTS[i] == cur_start: opt_start.select(i)
	start_vbox.add_child(opt_start)
	dt_hbox.add_child(start_vbox)

	var end_vbox = VBoxContainer.new(); end_vbox.custom_minimum_size = Vector2(160, 0)
	var lbl_end = Label.new(); lbl_end.text = "End Time *"; lbl_end.add_theme_font_size_override("font_size", 13); lbl_end.add_theme_color_override("font_color", Color(0.20, 0.26, 0.34, 1.0))
	end_vbox.add_child(lbl_end)
	var opt_end = OptionButton.new(); opt_end.custom_minimum_size = Vector2(0, 40)
	for t in STANDARD_TIME_SLOTS: opt_end.add_item(t)
	var cur_end = str(session_data.get("end_time", "10:30 AM"))
	for i in range(STANDARD_TIME_SLOTS.size()):
		if STANDARD_TIME_SLOTS[i] == cur_end: opt_end.select(i)
	end_vbox.add_child(opt_end)
	dt_hbox.add_child(end_vbox)

	dt_card.add_child(dt_hbox)
	mvbox.add_child(dt_card)

	# ---------------- GROUP 3: STAFFING REQUIREMENT ----------------
	var g_staff_lbl = Label.new(); g_staff_lbl.text = "3. Staffing Requirement"; g_staff_lbl.add_theme_font_size_override("font_size", 16); g_staff_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	mvbox.add_child(g_staff_lbl)

	var g_staff_card = _create_group_card.call()
	var staff_vbox = VBoxContainer.new(); staff_vbox.add_theme_constant_override("separation", 10)

	var cur_staff_req = str(session_data.get("staffing_requirement", "DEDICATED_SESSION_STAFF"))

	var chk_dedicated = CheckBox.new()
	_style_checkbox(chk_dedicated)
	chk_dedicated.text = "Dedicated Session Staff Required"
	chk_dedicated.button_pressed = (cur_staff_req != "COVERED_BY_STUDY_CENTER_STAFF")
	staff_vbox.add_child(chk_dedicated)

	var chk_covered_by_staff = CheckBox.new()
	_style_checkbox(chk_covered_by_staff)
	chk_covered_by_staff.text = "Covered by Study Center Staff"
	chk_covered_by_staff.button_pressed = (cur_staff_req == "COVERED_BY_STUDY_CENTER_STAFF")
	staff_vbox.add_child(chk_covered_by_staff)

	# Radio Button Mutual Exclusivity Handler
	chk_dedicated.toggled.connect(func(pressed: bool):
		if pressed: chk_covered_by_staff.button_pressed = false
		elif not chk_covered_by_staff.button_pressed: chk_dedicated.button_pressed = true
	)
	chk_covered_by_staff.toggled.connect(func(pressed: bool):
		if pressed: chk_dedicated.button_pressed = false
		elif not chk_dedicated.button_pressed: chk_dedicated.button_pressed = true
	)

	g_staff_card.add_child(staff_vbox)
	mvbox.add_child(g_staff_card)

	# ---------------- GROUP 4: LOCATIONS & EXCLUSIVITY ----------------
	var g3_lbl = Label.new(); g3_lbl.text = "4. Session Locations"; g3_lbl.add_theme_font_size_override("font_size", 16); g3_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	mvbox.add_child(g3_lbl)

	var g3_card = _create_group_card.call()
	var loc_grid = GridContainer.new(); loc_grid.columns = 2; loc_grid.add_theme_constant_override("h_separation", 16); loc_grid.add_theme_constant_override("v_separation", 8)

	var all_locs = []
	if config_service:
		all_locs = config_service.get_all_session_locations(true)

	var initial_loc_ids = []
	if is_edit_mode and sch_service:
		initial_loc_ids = sch_service.get_session_location_ids(target_session_id)

	var location_checkboxes = [] # Array of {"checkbox": CheckBox, "id": int, "exclusive": bool}

	for l in all_locs:
		var l_id = int(l["id"])
		var l_name = str(l["name"])
		var l_excl = int(l.get("is_exclusive", 0)) == 1
		var l_active = int(l.get("is_active", 1)) == 1

		# Show active locations or currently assigned inactive location
		if l_active or (l_id in initial_loc_ids):
			var chk = CheckBox.new()
			_style_checkbox(chk)
			var loc_display_text = l_name
			if l_excl:
				loc_display_text += " ⭐ (Exclusive)"
			elif not l_active:
				loc_display_text += " [Inactive]"

			chk.text = loc_display_text
			chk.button_pressed = (l_id in initial_loc_ids)

			var entry = {"checkbox": chk, "id": l_id, "exclusive": l_excl}
			location_checkboxes.append(entry)
			loc_grid.add_child(chk)

	# Exclusive location interaction logic handler
	for entry in location_checkboxes:
		var chk_ref = entry["checkbox"]
		var is_excl_ref = entry["exclusive"]

		chk_ref.toggled.connect(func(pressed: bool):
			if pressed:
				if is_excl_ref:
					# Clear and disable all other checkboxes
					for other in location_checkboxes:
						if other != entry:
							other["checkbox"].button_pressed = false
							other["checkbox"].disabled = true
				else:
					# Standard location checked: ensure Exclusive checkboxes are cleared & uncheck other exclusive
					for other in location_checkboxes:
						if other["exclusive"]:
							other["checkbox"].button_pressed = false
							other["checkbox"].disabled = true
			else:
				# Re-evaluate disabling states if all unchecked
				var any_std_checked = false
				var any_excl_checked = false
				for other in location_checkboxes:
					if other["checkbox"].button_pressed:
						if other["exclusive"]: any_excl_checked = true
						else: any_std_checked = true

				for other in location_checkboxes:
					if any_excl_checked:
						other["checkbox"].disabled = not other["checkbox"].button_pressed
					elif any_std_checked:
						other["checkbox"].disabled = other["exclusive"]
					else:
						other["checkbox"].disabled = false
		)

	# Run initial state setup
	for entry in location_checkboxes:
		if entry["checkbox"].button_pressed:
			entry["checkbox"].toggled.emit(true)
			break

	g3_card.add_child(loc_grid)
	mvbox.add_child(g3_card)

	# ---------------- GROUP 4: SIGNUP & CAPACITY POLICY ----------------
	var g4_lbl = Label.new(); g4_lbl.text = "4. Signup & Capacity Policy"; g4_lbl.add_theme_font_size_override("font_size", 16); g4_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	mvbox.add_child(g4_lbl)

	var g4_card = _create_group_card.call()
	var policy_hbox = HBoxContainer.new(); policy_hbox.add_theme_constant_override("separation", 16)

	# Signup Required Mode
	var opt_signup_mode = OptionButton.new(); opt_signup_mode.custom_minimum_size = Vector2(180, 38)
	opt_signup_mode.add_item("Signup Required", 0)
	opt_signup_mode.add_item("Signup Not Required", 1)
	var init_req = int(session_data.get("signup_required", 1))
	opt_signup_mode.select(0 if init_req == 1 else 1)
	policy_hbox.add_child(opt_signup_mode)

	# Limit Signups Checkbox
	var chk_limit = CheckBox.new()
	_style_checkbox(chk_limit)
	chk_limit.text = "Limit Signups for This Session"
	chk_limit.button_pressed = int(session_data.get("limit_signups", 1)) == 1
	policy_hbox.add_child(chk_limit)

	# Maximum Capacity Input
	var cap_vbox = VBoxContainer.new()
	var lbl_cap = Label.new(); lbl_cap.text = "Max Participants *"; lbl_cap.add_theme_font_size_override("font_size", 13)
	cap_vbox.add_child(lbl_cap)
	var input_cap = SpinBox.new(); input_cap.min_value = 1; input_cap.max_value = 500; input_cap.value = int(session_data.get("max_capacity", 30))
	input_cap.custom_minimum_size = Vector2(130, 38)
	cap_vbox.add_child(input_cap)
	policy_hbox.add_child(cap_vbox)

	g4_card.add_child(policy_hbox)
	mvbox.add_child(g4_card)

	var update_policy_states = func(val = 0):
		var req = (opt_signup_mode.selected == 0)
		chk_limit.disabled = not req
		if not req:
			chk_limit.button_pressed = false
			cap_vbox.visible = false
		else:
			cap_vbox.visible = chk_limit.button_pressed

	opt_signup_mode.item_selected.connect(update_policy_states)
	chk_limit.toggled.connect(update_policy_states)
	update_policy_states.call()

	# ---------------- GROUP 5: OPTIONAL OVERRIDES ----------------
	var g5_lbl = Label.new(); g5_lbl.text = "5. Optional Reporting Overrides"; g5_lbl.add_theme_font_size_override("font_size", 16); g5_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	mvbox.add_child(g5_lbl)

	var g5_card = _create_group_card.call()
	var ov_hbox = HBoxContainer.new(); ov_hbox.add_theme_constant_override("separation", 10)
	var input_term_ov = LineEdit.new(); input_term_ov.placeholder_text = "Term Override (e.g. Fall 2026)"; input_term_ov.text = _clean_str.call(session_data.get("term_override"), ""); input_term_ov.custom_minimum_size = Vector2(240, 38)
	var input_type_ov = LineEdit.new(); input_type_ov.placeholder_text = "Type Override (Optional)"; input_type_ov.text = _clean_str.call(session_data.get("type_override"), ""); input_type_ov.custom_minimum_size = Vector2(240, 38)
	ov_hbox.add_child(input_term_ov); ov_hbox.add_child(input_type_ov)
	g5_card.add_child(ov_hbox)
	mvbox.add_child(g5_card)

	scroll.add_child(mvbox)
	margin.add_child(scroll)

	# Build Initial Form Snapshot for Unsaved Changes Tracking
	var get_current_form_snapshot = func() -> Dictionary:
		var loc_ids_curr = []
		for entry in location_checkboxes:
			if entry["checkbox"].button_pressed: loc_ids_curr.append(entry["id"])
		return {
			"type_idx": opt_type.selected,
			"title": input_title.text,
			"description": input_desc.text,
			"date": input_date.text,
			"start": opt_start.selected,
			"end": opt_end.selected,
			"locations": loc_ids_curr,
			"signup_mode": opt_signup_mode.selected,
			"limit_signups": chk_limit.button_pressed,
			"max_capacity": input_cap.value,
			"term_override": input_term_ov.text,
			"type_override": input_type_ov.text
		}

	var initial_snapshot = get_current_form_snapshot.call()

	var is_form_dirty = func() -> bool:
		var curr_snap = get_current_form_snapshot.call()
		return JSON.stringify(curr_snap) != JSON.stringify(initial_snapshot)

	# ---------------- ACTION BUTTONS ----------------
	var btn_hbox = HBoxContainer.new(); btn_hbox.add_theme_constant_override("separation", 14); btn_hbox.alignment = BoxContainer.ALIGNMENT_END

	var btn_cancel = Button.new(); btn_cancel.text = "❌ Cancel"; btn_cancel.custom_minimum_size = Vector2(100, 40)
	_style_outline_button(btn_cancel)

	# Unsaved Changes Confirmation Handler on Cancel
	btn_cancel.pressed.connect(func():
		if not is_form_dirty.call():
			dialog.queue_free()
			return

		var confirm_dialog = Window.new()
		confirm_dialog.title = "⚠️ Discard Unsaved Changes?"
		confirm_dialog.size = Vector2i(440, 180)
		confirm_dialog.exclusive = true
		confirm_dialog.transient = true
		confirm_dialog.close_requested.connect(func(): confirm_dialog.queue_free())

		var c_margin = MarginContainer.new()
		c_margin.set_anchors_preset(PRESET_FULL_RECT)
		c_margin.add_theme_constant_override("margin_left", 20); c_margin.add_theme_constant_override("margin_top", 16); c_margin.add_theme_constant_override("margin_right", 20); c_margin.add_theme_constant_override("margin_bottom", 16)

		var c_vbox = VBoxContainer.new(); c_vbox.add_theme_constant_override("separation", 16)
		var c_lbl = Label.new(); c_lbl.text = "You have unsaved changes. Are you sure you want to discard your edits?"
		c_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c_vbox.add_child(c_lbl)

		var c_btn_hbox = HBoxContainer.new(); c_btn_hbox.add_theme_constant_override("separation", 12); c_btn_hbox.alignment = BoxContainer.ALIGNMENT_END

		var btn_continue = Button.new(); btn_continue.text = "Continue Editing"; btn_continue.custom_minimum_size = Vector2(140, 36)
		_style_outline_button(btn_continue)
		btn_continue.pressed.connect(func(): confirm_dialog.queue_free())
		c_btn_hbox.add_child(btn_continue)

		var btn_discard = Button.new(); btn_discard.text = "Discard Changes"; btn_discard.custom_minimum_size = Vector2(140, 36)
		var d_st = StyleBoxFlat.new(); d_st.bg_color = Color(0.75, 0.15, 0.15, 1.0); d_st.corner_radius_top_left = 6; d_st.corner_radius_top_right = 6; d_st.corner_radius_bottom_left = 6; d_st.corner_radius_bottom_right = 6
		btn_discard.add_theme_stylebox_override("normal", d_st)
		btn_discard.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn_discard.pressed.connect(func():
			confirm_dialog.queue_free()
			dialog.queue_free()
		)
		c_btn_hbox.add_child(btn_discard)

		c_vbox.add_child(c_btn_hbox)
		c_margin.add_child(c_vbox)
		confirm_dialog.add_child(c_margin)
		dialog.add_child(confirm_dialog)
		confirm_dialog.popup_centered()
	)

	dialog.close_requested.connect(func(): btn_cancel.pressed.emit())
	btn_hbox.add_child(btn_cancel)

	var btn_save = Button.new()
	if is_edit_mode:
		btn_save.text = "💾 Save Changes"
	else:
		btn_save.text = "➕ Save Session"
	btn_save.custom_minimum_size = Vector2(150, 40)
	var btn_st = StyleBoxFlat.new(); btn_st.bg_color = Color(0.88, 0.35, 0.21, 1.0); btn_st.corner_radius_top_left = 6; btn_st.corner_radius_top_right = 6; btn_st.corner_radius_bottom_left = 6; btn_st.corner_radius_bottom_right = 6
	btn_save.add_theme_stylebox_override("normal", btn_st)
	btn_save.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_save.pressed.connect(func():
		var clean_title = input_title.text.strip_edges()
		if clean_title == "":
			err_banner.text = "❌ Session Title is required."
			err_banner.visible = true
			input_title.grab_focus()
			return

		var s_type_id = 6
		if opt_type.selected >= 0 and opt_type.selected < type_id_map.size():
			s_type_id = type_id_map[opt_type.selected]

		var date_text = input_date.text.strip_edges()
		var start_t = opt_start.get_item_text(opt_start.selected)
		var end_t = opt_end.get_item_text(opt_end.selected)

		# Validate Start Time before End Time
		var start_idx = opt_start.selected
		var end_idx = opt_end.selected
		if end_idx <= start_idx:
			err_banner.text = "❌ End Time must occur after Start Time."
			err_banner.visible = true
			return

		# Collect Location Assignments
		var loc_ids = []
		for entry in location_checkboxes:
			if entry["checkbox"].button_pressed: loc_ids.append(entry["id"])

		var req_val = 1 if opt_signup_mode.selected == 0 else 0
		var lim_val = 0
		if req_val == 1 and chk_limit.button_pressed:
			lim_val = 1
		var cap_val = int(input_cap.value)
		var sel_staffing_req = "COVERED_BY_STUDY_CENTER_STAFF" if chk_covered_by_staff.button_pressed else "DEDICATED_SESSION_STAFF"

		btn_save.disabled = true

		var save_res = {}
		if is_edit_mode:
			save_res = sch_service.update_full_session_atomic(target_session_id, clean_title, s_type_id, date_text, start_t, end_t, cap_val, req_val, lim_val, loc_ids, input_desc.text, input_term_ov.text, input_type_ov.text, "usr_admin_master", "Administrator", "", false, sel_staffing_req)
		else:
			save_res = sch_service.create_full_session_atomic(clean_title, s_type_id, date_text, start_t, end_t, "Gathering Room", cap_val, req_val, lim_val, loc_ids, input_desc.text, "Administrator", input_term_ov.text, input_type_ov.text, "usr_admin_master", "", false, sel_staffing_req)

		if save_res["success"]:
			dialog.queue_free()
			call_deferred("_refresh_tab_content")
		else:
			btn_save.disabled = false
			err_banner.text = "❌ Save error: " + save_res["error"]
			err_banner.visible = true
	)
	btn_hbox.add_child(btn_save)

	mvbox.add_child(btn_hbox)
	add_child(dialog)
	dialog.popup_centered()

# ==================== TAB 2: STUDENT SCHEDULED SESSIONS ====================

func open_session_communication_composer(session_data: Dictionary = {}) -> void:
	if not sch_service and db: sch_service = SchedulesServiceScript.new(db)
	var sess_id = int(session_data.get("id", 0))

	var dialog = Window.new()
	dialog.title = "✉️ Session Communication Composer: " + str(session_data.get("title", "Session"))
	dialog.size = Vector2i(700, 750)
	dialog.exclusive = true
	dialog.transient = true

	var margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20); margin.add_theme_constant_override("margin_top", 16); margin.add_theme_constant_override("margin_right", 20); margin.add_theme_constant_override("margin_bottom", 16)

	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL
	var cvbox = VBoxContainer.new(); cvbox.size_flags_horizontal = SIZE_EXPAND_FILL; cvbox.add_theme_constant_override("separation", 12)

	# 1. Audience Selector
	var aud_label = Label.new(); aud_label.text = "Target Audience:"
	cvbox.add_child(aud_label)
	var opt_aud = OptionButton.new()
	opt_aud.add_item("All Participants (Confirmed & Waitlist)", 0)
	opt_aud.add_item("Confirmed Participants Only", 1)
	opt_aud.add_item("Waiting List Participants Only", 2)
	opt_aud.add_item("Communication Needed Only", 3)
	cvbox.add_child(opt_aud)

	# 2. Recipient Summary & Badges
	var summary_lbl = Label.new()
	summary_lbl.text = "📊 Recipients Summary: 4 Selected | SMS Eligible: 3 | Email Eligible: 4 | Excluded: 1"
	summary_lbl.add_theme_color_override("font_color", Color(0.2, 0.4, 0.7, 1.0))
	cvbox.add_child(summary_lbl)

	var ex_lbl = Label.new()
	ex_lbl.text = "⚠️ Exclusions: Diana Prince (SMS Consent Withdrawn - STOP Opt-Out)"
	ex_lbl.add_theme_color_override("font_color", Color(0.7, 0.2, 0.2, 1.0))
	cvbox.add_child(ex_lbl)

	# 3. Channel Selector
	var chan_lbl = Label.new(); chan_lbl.text = "Dispatch Channel:"
	cvbox.add_child(chan_lbl)
	var opt_chan = OptionButton.new()
	opt_chan.add_item("SMS (Twilio Gateway)", 0)
	opt_chan.add_item("Email (Outbox Relay)", 1)
	opt_chan.add_item("Both (SMS + Email)", 2)
	cvbox.add_child(opt_chan)

	# 4. Template Selector
	var tmpl_lbl = Label.new(); tmpl_lbl.text = "Communication Template:"
	cvbox.add_child(tmpl_lbl)
	var opt_tmpl = OptionButton.new()
	opt_tmpl.add_item("General Session Reminder", 0)
	opt_tmpl.add_item("Waiting-List Update", 1)
	opt_tmpl.add_item("Promotion Confirmation", 2)
	opt_tmpl.add_item("Removal or Cancellation Notice", 3)
	opt_tmpl.add_item("Session Time Change", 4)
	opt_tmpl.add_item("Session Location Change", 5)
	cvbox.add_child(opt_tmpl)

	# 5. Email Subject & Message Body
	var subj_lbl = Label.new(); subj_lbl.text = "Subject (for Email):"
	cvbox.add_child(subj_lbl)
	var txt_subj = LineEdit.new()
	txt_subj.text = "Notice regarding " + str(session_data.get("title", "Session"))
	cvbox.add_child(txt_subj)

	var body_lbl = Label.new(); body_lbl.text = "Message Body:"
	cvbox.add_child(body_lbl)
	var txt_body = TextEdit.new()
	txt_body.custom_minimum_size = Vector2(0, 100)
	txt_body.text = "Hello {first_name}, notice regarding your session '{session_title}' on {date} at {time}."
	cvbox.add_child(txt_body)

	# 6. Merge Preview
	var preview_lbl = Label.new()
	preview_lbl.text = "🔍 Preview: Hello Bob, notice regarding your session 'Physics Workshop' on 2026-07-30 at 02:00 PM."
	preview_lbl.add_theme_color_override("font_color", Color(0.3, 0.5, 0.3, 1.0))
	cvbox.add_child(preview_lbl)

	# 7. Attachment Selection
	var att_hbox = HBoxContainer.new()
	var txt_att = LineEdit.new(); txt_att.placeholder_text = "Attachment path (e.g. res://icon.svg)"; txt_att.size_flags_horizontal = SIZE_EXPAND_FILL
	var btn_att_rem = Button.new(); btn_att_rem.text = "Clear Attachment"
	btn_att_rem.pressed.connect(func(): txt_att.text = "")
	att_hbox.add_child(txt_att); att_hbox.add_child(btn_att_rem)
	cvbox.add_child(att_hbox)

	# 8. Feedback Banner
	var res_lbl = Label.new()
	res_lbl.text = ""
	cvbox.add_child(res_lbl)

	# 9. Action Buttons
	var btn_hbox = HBoxContainer.new(); btn_hbox.add_theme_constant_override("separation", 10)

	var btn_send = Button.new(); btn_send.text = "🚀 Send Now"; btn_send.custom_minimum_size = Vector2(110, 36)
	_style_primary_button(btn_send)
	btn_send.pressed.connect(func():
		btn_send.disabled = true # Prevent duplicate click
		var aud_val = "all" if opt_aud.selected == 0 else ("confirmed" if opt_aud.selected == 1 else "waitlist")
		var chan_val = "SMS" if opt_chan.selected == 0 else ("Email" if opt_chan.selected == 1 else "Both")
		var res = sch_service.send_session_communication_atomic(sess_id, aud_val, chan_val, txt_subj.text, txt_body.text, txt_body.text, [], txt_att.text)
		res_lbl.text = "✅ Dispatched: " + str(res.get("sent_count", 0)) + " sent | Excluded: " + str(res.get("excluded_count", 0))
		res_lbl.add_theme_color_override("font_color", Color(0.1, 0.6, 0.2, 1.0))
	)
	btn_hbox.add_child(btn_send)

	var btn_draft = Button.new(); btn_draft.text = "💾 Save Draft"; btn_draft.custom_minimum_size = Vector2(110, 36)
	_style_outline_button(btn_draft)
	btn_draft.pressed.connect(func():
		var cs = sch_service._get_comms_service()
		cs.save_message_draft_atomic(sess_id, "all", "SMS", txt_body.text, "usr_admin_master")
		res_lbl.text = "💾 Draft saved locally."
	)
	btn_hbox.add_child(btn_draft)

	var btn_sched = Button.new(); btn_sched.text = "⏰ Schedule"; btn_sched.custom_minimum_size = Vector2(100, 36)
	_style_outline_button(btn_sched)
	btn_sched.pressed.connect(func():
		var cs = sch_service._get_comms_service()
		cs.schedule_message_atomic(sess_id, "all", "SMS", txt_body.text, "2026-08-01 10:00 AM", "usr_admin_master")
		res_lbl.text = "⏰ Communication scheduled."
	)
	btn_hbox.add_child(btn_sched)

	var btn_close = Button.new(); btn_close.text = "Cancel"; btn_close.custom_minimum_size = Vector2(90, 36)
	btn_close.pressed.connect(func(): dialog.queue_free())
	btn_hbox.add_child(btn_close)

	cvbox.add_child(btn_hbox)
	scroll.add_child(cvbox)
	margin.add_child(scroll)
	dialog.add_child(margin)

	add_child(dialog)
	dialog.popup_centered()

func _render_sessions_tab() -> void:
	var split_hbox = HBoxContainer.new(); split_hbox.size_flags_vertical = SIZE_EXPAND_FILL; split_hbox.add_theme_constant_override("separation", 16)
	var left_vbox = VBoxContainer.new(); left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL; left_vbox.add_theme_constant_override("separation", 12)

	# ---------------- TOP TOOLBAR ----------------
	var top_bar = HBoxContainer.new(); top_bar.add_theme_constant_override("separation", 12)

	var h_hbox = HBoxContainer.new(); h_hbox.add_theme_constant_override("separation", 8); h_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	var horizons = ["all", "today", "future", "past"]
	for hz in horizons:
		var btn = Button.new(); btn.text = hz.capitalize(); btn.custom_minimum_size = Vector2(90, 36)
		if hz == active_session_horizon:
			_style_primary_button(btn)
		else:
			_style_outline_button(btn)
		btn.pressed.connect(func(): active_session_horizon = hz; call_deferred("_refresh_tab_content"))
		h_hbox.add_child(btn)
	top_bar.add_child(h_hbox)

	var btn_new_session = Button.new(); btn_new_session.text = "➕ Create New Session"; btn_new_session.custom_minimum_size = Vector2(170, 36)
	_style_primary_button(btn_new_session)
	btn_new_session.pressed.connect(func(): open_session_editor_modal({}))
	top_bar.add_child(btn_new_session)

	left_vbox.add_child(top_bar)

	# ---------------- SESSION TYPE MULTI-SELECT FILTER BAR ----------------
	var filter_vbox = VBoxContainer.new(); filter_vbox.add_theme_constant_override("separation", 6)
	var flbl_hbox = HBoxContainer.new(); flbl_hbox.add_theme_constant_override("separation", 10)
	var flbl = Label.new(); flbl.text = "🔍 Filter by Session Type:"; flbl.add_theme_font_size_override("font_size", 13); flbl.add_theme_color_override("font_color", Color(0.30, 0.38, 0.48, 1.0))
	flbl_hbox.add_child(flbl)

	if selected_filter_type_ids.size() > 0:
		var btn_clear_f = Button.new(); btn_clear_f.text = "Clear Filter (Show All)"; btn_clear_f.custom_minimum_size = Vector2(130, 26); btn_clear_f.add_theme_font_size_override("font_size", 12)
		_style_outline_button(btn_clear_f)
		btn_clear_f.pressed.connect(func(): selected_filter_type_ids.clear(); call_deferred("_refresh_tab_content"))
		flbl_hbox.add_child(btn_clear_f)

	filter_vbox.add_child(flbl_hbox)

	var f_hbox = HBoxContainer.new(); f_hbox.add_theme_constant_override("separation", 8)
	var active_types = config_service.get_all_session_types(false) if config_service else []
	for st in active_types:
		var st_id = int(st["id"])
		var st_name = str(st["name"])
		var chk_f = CheckBox.new(); chk_f.text = st_name
		_style_checkbox(chk_f)
		chk_f.button_pressed = (st_id in selected_filter_type_ids)
		chk_f.toggled.connect(func(pressed: bool):
			if pressed and not (st_id in selected_filter_type_ids):
				selected_filter_type_ids.append(st_id)
			elif not pressed and (st_id in selected_filter_type_ids):
				selected_filter_type_ids.erase(st_id)
			call_deferred("_refresh_tab_content")
		)
		f_hbox.add_child(chk_f)

	filter_vbox.add_child(f_hbox)
	left_vbox.add_child(filter_vbox)

	# ---------------- SESSION CARDS SCROLL LIST ----------------
	var scroll = ScrollContainer.new(); scroll.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.size_flags_vertical = SIZE_EXPAND_FILL
	var svbox = VBoxContainer.new(); svbox.size_flags_horizontal = SIZE_EXPAND_FILL; svbox.add_theme_constant_override("separation", 12)

	var sessions = sch_service.get_phase4_sessions_aggregate(active_session_horizon, selected_filter_type_ids) if sch_service else []

	if sessions.size() > 0:
		selected_session_id = int(sessions[0].get("id", 1))
		for s in sessions:
			var s_id = int(s.get("id"))
			var stitle = str(s.get("title", ""))
			var stype_name = str(s.get("session_type_name", "General"))
			var stype_active = int(s.get("session_type_active", 1)) == 1
			var sdate = str(s.get("date_text", ""))
			var sday = str(s.get("day_of_week", "Scheduled Date"))
			var stime = str(s.get("start_time", "")) + " - " + str(s.get("end_time", ""))
			var sdesc = str(s.get("description", "")).strip_edges()
			var req = int(s.get("signup_required", 1)) == 1
			var lim = int(s.get("limit_signups", 1)) == 1
			var cap = int(s.get("max_capacity", 30))
			var conf_cnt = int(s.get("confirmed_count", 0))
			var wait_cnt = int(s.get("waitlist_count", 0))
			var locs = s.get("locations", [])

			var card = PanelContainer.new()
			var c_st = StyleBoxFlat.new()
			c_st.bg_color = Color(0.98, 0.99, 1.0, 1.0)
			c_st.border_width_left = 1; c_st.border_width_top = 1; c_st.border_width_right = 1; c_st.border_width_bottom = 1
			c_st.border_color = Color(0.86, 0.90, 0.95, 1.0)
			c_st.corner_radius_top_left = 8; c_st.corner_radius_top_right = 8; c_st.corner_radius_bottom_left = 8; c_st.corner_radius_bottom_right = 8
			c_st.content_margin_left = 16; c_st.content_margin_top = 14; c_st.content_margin_right = 16; c_st.content_margin_bottom = 14
			card.add_theme_stylebox_override("panel", c_st)

			var card_vbox = VBoxContainer.new(); card_vbox.add_theme_constant_override("separation", 8)

			# Header Row: Title, Date, Time & Session Type Badge
			var h_row = HBoxContainer.new(); h_row.add_theme_constant_override("separation", 12)
			var title_lbl = Label.new()
			var type_badge = stype_name if stype_active else stype_name + " [Inactive]"
			title_lbl.text = "📅 " + stitle + " [" + type_badge + "]"
			title_lbl.add_theme_font_size_override("font_size", 16); title_lbl.add_theme_color_override("font_color", Color(0.10, 0.14, 0.20, 1.0))
			title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			h_row.add_child(title_lbl)

			var time_lbl = Label.new()
			time_lbl.text = sday + ", " + sdate + " • " + stime
			time_lbl.add_theme_font_size_override("font_size", 13); time_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
			h_row.add_child(time_lbl)
			card_vbox.add_child(h_row)

			# Location Badges Row
			var loc_row = HBoxContainer.new(); loc_row.add_theme_constant_override("separation", 8)
			var loc_lbl_title = Label.new(); loc_lbl_title.text = "📍 Locations:"; loc_lbl_title.add_theme_font_size_override("font_size", 13); loc_lbl_title.add_theme_color_override("font_color", Color(0.40, 0.46, 0.54, 1.0))
			loc_row.add_child(loc_lbl_title)

			if locs.size() > 0:
				for loc_item in locs:
					var lname = str(loc_item["name"])
					var lexcl = int(loc_item.get("is_exclusive", 0)) == 1
					var lactive = int(loc_item.get("is_active", 1)) == 1
					var loc_disp = (lname + " ⭐") if lexcl else (lname if lactive else lname + " [Inactive]")
					var loc_badge = Label.new(); loc_badge.text = "• " + loc_disp; loc_badge.add_theme_font_size_override("font_size", 13); loc_badge.add_theme_color_override("font_color", Color(0.18, 0.40, 0.65, 1.0))
					loc_row.add_child(loc_badge)
			else:
				var no_loc = Label.new(); no_loc.text = "• Unassigned Location"; no_loc.add_theme_font_size_override("font_size", 13); no_loc.add_theme_color_override("font_color", Color(0.60, 0.65, 0.72, 1.0))
				loc_row.add_child(no_loc)

			card_vbox.add_child(loc_row)

			# Description Display (derived fallback if empty)
			var desc_lbl = Label.new()
			desc_lbl.text = sdesc if sdesc != "" else "No additional description"
			desc_lbl.add_theme_font_size_override("font_size", 13)
			desc_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.38, 1.0) if sdesc != "" else Color(0.60, 0.65, 0.72, 1.0))
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card_vbox.add_child(desc_lbl)

			# Policy & Capacity State Row
			var cap_row = HBoxContainer.new(); cap_row.add_theme_constant_override("separation", 12)
			
			if not req:
				var p_lbl = Label.new(); p_lbl.text = "ℹ️ Signup Not Required"; p_lbl.add_theme_font_size_override("font_size", 13); p_lbl.add_theme_color_override("font_color", Color(0.20, 0.55, 0.30, 1.0))
				cap_row.add_child(p_lbl)
			elif not lim:
				var p_lbl = Label.new(); p_lbl.text = "👥 Signup Required · Unlimited Capacity (Confirmed: " + str(conf_cnt) + ")"; p_lbl.add_theme_font_size_override("font_size", 13); p_lbl.add_theme_color_override("font_color", Color(0.15, 0.45, 0.75, 1.0))
				cap_row.add_child(p_lbl)
			else:
				var rem = max(0, cap - conf_cnt)
				var cap_text = "👥 Confirmed: " + str(conf_cnt) + " / " + str(cap)
				var pct = min(100, int((float(conf_cnt) / float(cap)) * 100.0))
				cap_text += " (" + str(pct) + "%)"

				var status_badge = ""
				var status_color = Color(0.15, 0.45, 0.75, 1.0)

				if conf_cnt >= cap:
					if wait_cnt > 0:
						status_badge = " • ⚠️ Full · Waitlist Active (" + str(wait_cnt) + " waiting)"
						status_color = Color(0.80, 0.40, 0.10, 1.0)
					else:
						status_badge = " • ⛔ Full"
						status_color = Color(0.75, 0.20, 0.20, 1.0)
				else:
					status_badge = " • ✅ Spaces Available (" + str(rem) + " remaining)"
					status_color = Color(0.18, 0.55, 0.28, 1.0)

				var cap_lbl = Label.new(); cap_lbl.text = cap_text + status_badge; cap_lbl.add_theme_font_size_override("font_size", 13); cap_lbl.add_theme_color_override("font_color", status_color)
				cap_row.add_child(cap_lbl)

			card_vbox.add_child(cap_row)

			# Action Buttons Row: Edit Session & Open Session Assistant
			var act_row = HBoxContainer.new(); act_row.add_theme_constant_override("separation", 10); act_row.alignment = BoxContainer.ALIGNMENT_END

			var cur_sess = s
			var btn_edit = Button.new(); btn_edit.text = "✏️ Edit Session"; btn_edit.custom_minimum_size = Vector2(110, 34); btn_edit.add_theme_font_size_override("font_size", 13)
			_style_outline_button(btn_edit)
			btn_edit.pressed.connect(func(): open_session_editor_modal(cur_sess))
			act_row.add_child(btn_edit)

			var btn_asst = Button.new(); btn_asst.text = "🚀 Open Session Assistant"; btn_asst.custom_minimum_size = Vector2(185, 34); btn_asst.add_theme_font_size_override("font_size", 13)
			_style_primary_button(btn_asst)
			btn_asst.pressed.connect(func(): open_session_assistant_placeholder(cur_sess))
			act_row.add_child(btn_asst)

			card_vbox.add_child(act_row)
			card.add_child(card_vbox)
			svbox.add_child(card)
	else:
		var empty_panel = PanelContainer.new()
		var ep_st = StyleBoxFlat.new(); ep_st.bg_color = Color(0.98, 0.99, 1.0, 1.0); ep_st.border_width_left = 1; ep_st.border_width_top = 1; ep_st.border_width_right = 1; ep_st.border_width_bottom = 1
		ep_st.border_color = Color(0.88, 0.91, 0.95, 1.0); ep_st.corner_radius_top_left = 8; ep_st.corner_radius_top_right = 8; ep_st.corner_radius_bottom_left = 8; ep_st.corner_radius_bottom_right = 8
		ep_st.content_margin_left = 20; ep_st.content_margin_top = 20; ep_st.content_margin_right = 20; ep_st.content_margin_bottom = 20
		empty_panel.add_theme_stylebox_override("panel", ep_st)

		var evbox = VBoxContainer.new(); evbox.add_theme_constant_override("separation", 10)
		var elbl = Label.new()
		if selected_filter_type_ids.size() > 0:
			elbl.text = "🔍 No sessions match the selected Session Type filter(s)."
		else:
			elbl.text = "📅 No sessions found for selected time horizon."
		elbl.add_theme_font_size_override("font_size", 14); elbl.add_theme_color_override("font_color", Color(0.40, 0.48, 0.58, 1.0))
		evbox.add_child(elbl)

		if selected_filter_type_ids.size() > 0:
			var btn_reset_f = Button.new(); btn_reset_f.text = "Clear Filter Selection"; btn_reset_f.custom_minimum_size = Vector2(160, 34)
			_style_outline_button(btn_reset_f)
			btn_reset_f.pressed.connect(func(): selected_filter_type_ids.clear(); call_deferred("_refresh_tab_content"))
			evbox.add_child(btn_reset_f)

		empty_panel.add_child(evbox)
		svbox.add_child(empty_panel)

	scroll.add_child(svbox)
	left_vbox.add_child(scroll)
	split_hbox.add_child(left_vbox)

	var waitlist_card = PanelContainer.new(); waitlist_card.custom_minimum_size = Vector2(320, 0)
	var wst = StyleBoxFlat.new(); wst.bg_color = Color(0.98, 0.99, 1.0, 1.0); wst.border_width_left = 1; wst.border_width_top = 1; wst.border_width_right = 1; wst.border_width_bottom = 1
	wst.border_color = Color(0.88, 0.91, 0.95, 1.0); wst.corner_radius_top_left = 8; wst.corner_radius_top_right = 8; wst.corner_radius_bottom_left = 8; wst.corner_radius_bottom_right = 8
	wst.content_margin_left = 12; wst.content_margin_top = 12; wst.content_margin_right = 12; wst.content_margin_bottom = 12
	waitlist_card.add_theme_stylebox_override("panel", wst)

	var wvbox = VBoxContainer.new(); wvbox.add_theme_constant_override("separation", 10)
	var w_title = Label.new(); w_title.text = "⏳ Session Waitlist Priority Queue"; w_title.add_theme_font_size_override("font_size", 15); w_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	wvbox.add_child(w_title)

	var signups = sch_service.get_signups_for_session(selected_session_id) if sch_service else []
	if signups.size() > 0:
		for s in signups:
			var fn = str(s.get("first_name")) if s.get("first_name") != null else ""
			var ln = str(s.get("last_name")) if s.get("last_name") != null else ""
			var name = (fn + " " + ln).strip_edges()
			var status = str(s.get("signup_status", "registered"))
			var uuid_s = str(s.get("signup_uuid", ""))

			var row_h = HBoxContainer.new(); row_h.add_theme_constant_override("separation", 8)
			var r_lbl = Label.new(); r_lbl.text = ("✅ " if status == "registered" else "⏳ ") + name + " (" + status.capitalize() + ")"
			r_lbl.add_theme_font_size_override("font_size", 13); r_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			row_h.add_child(r_lbl)

			if status == "waitlist":
				var btn_prom = Button.new(); btn_prom.text = "⚡ Promote"; btn_prom.custom_minimum_size = Vector2(80, 28)
				btn_prom.pressed.connect(func():
					sch_service.promote_waitlist_atomic(uuid_s)
					call_deferred("_refresh_tab_content")
				)
				row_h.add_child(btn_prom)

			wvbox.add_child(row_h)
	else:
		var empty_w = Label.new(); empty_w.text = "No students on waitlist queue."; empty_w.add_theme_font_size_override("font_size", 13); empty_w.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		wvbox.add_child(empty_w)

	waitlist_card.add_child(wvbox)
	split_hbox.add_child(waitlist_card)

	content_card.add_child(split_hbox)

func _render_hours_tab() -> void:
	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 14)
	var title_lbl = Label.new(); title_lbl.text = "Center Weekly Operating Hours Schedule"; title_lbl.add_theme_font_size_override("font_size", 16); title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new(); sub_lbl.text = "Configure normal weekly operating hours. Use 'Open' checkmark to set day open status, and enable 'Split Shift' for double sessions."
	sub_lbl.add_theme_font_size_override("font_size", 12); sub_lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.65, 1.0))
	vbox.add_child(sub_lbl)

	var open_hours_list = sch_service.get_open_hours()
	var hours_map = {}
	for h in open_hours_list:
		hours_map[str(h.get("day_of_week"))] = h

	var ordered_days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

	var list_vbox = VBoxContainer.new(); list_vbox.add_theme_constant_override("separation", 10)

	for day_name in ordered_days:
		var h = hours_map.get(day_name, {"id": 1, "open_time": "09:00 AM", "close_time": "06:00 PM", "is_closed": 0, "has_split_shift": 0, "session2_start": "05:00 PM", "session2_end": "08:00 PM"})
		var id_val = int(h.get("id", 1))
		var open_t = str(h.get("open_time", "09:00 AM"))
		var close_t = str(h.get("close_time", "06:00 PM"))
		var is_closed = int(h.get("is_closed", 0)) == 1
		var has_split = int(h.get("has_split_shift", 0)) == 1
		var s2_start_t = str(h.get("session2_start", "05:00 PM"))
		var s2_end_t = str(h.get("session2_end", "08:00 PM"))

		var row_card = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
		st.border_color = Color(0.88, 0.91, 0.95, 1.0)
		st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
		st.content_margin_left = 16; st.content_margin_top = 12; st.content_margin_right = 16; st.content_margin_bottom = 12
		row_card.add_theme_stylebox_override("panel", st)

		var r_hbox = HBoxContainer.new(); r_hbox.add_theme_constant_override("separation", 12)

		var d_lbl = Label.new(); d_lbl.text = day_name; d_lbl.custom_minimum_size = Vector2(100, 0)
		d_lbl.add_theme_font_size_override("font_size", 14); d_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
		r_hbox.add_child(d_lbl)

		var chk_open = CheckBox.new(); chk_open.text = "Open"; chk_open.button_pressed = not is_closed
		chk_open.add_theme_font_size_override("font_size", 13)
		r_hbox.add_child(chk_open)

		var s1_lbl = Label.new(); s1_lbl.text = "Session 1:"; s1_lbl.add_theme_font_size_override("font_size", 12); s1_lbl.add_theme_color_override("font_color", Color(0.40, 0.48, 0.58, 1.0))
		r_hbox.add_child(s1_lbl)

		var opt_open = OptionButton.new(); opt_open.custom_minimum_size = Vector2(120, 34)
		for t in STANDARD_TIME_SLOTS: opt_open.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == open_t: opt_open.select(i)
		r_hbox.add_child(opt_open)

		var opt_close = OptionButton.new(); opt_close.custom_minimum_size = Vector2(120, 34)
		for t in STANDARD_TIME_SLOTS: opt_close.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == close_t: opt_close.select(i)
		r_hbox.add_child(opt_close)

		var chk_split = CheckBox.new(); chk_split.text = "Split Shift"; chk_split.button_pressed = has_split
		chk_split.add_theme_font_size_override("font_size", 12)
		r_hbox.add_child(chk_split)

		var s2_lbl = Label.new(); s2_lbl.text = "Session 2:"; s2_lbl.add_theme_font_size_override("font_size", 12); s2_lbl.add_theme_color_override("font_color", Color(0.40, 0.48, 0.58, 1.0))
		r_hbox.add_child(s2_lbl)

		var opt_s2_open = OptionButton.new(); opt_s2_open.custom_minimum_size = Vector2(120, 34)
		for t in STANDARD_TIME_SLOTS: opt_s2_open.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == s2_start_t: opt_s2_open.select(i)
		r_hbox.add_child(opt_s2_open)

		var opt_s2_close = OptionButton.new(); opt_s2_close.custom_minimum_size = Vector2(120, 34)
		for t in STANDARD_TIME_SLOTS: opt_s2_close.add_item(t)
		for i in range(STANDARD_TIME_SLOTS.size()):
			if STANDARD_TIME_SLOTS[i] == s2_end_t: opt_s2_close.select(i)
		r_hbox.add_child(opt_s2_close)

		var refresh_row_states = func():
			var is_open = chk_open.button_pressed
			var is_split = chk_split.button_pressed and is_open

			opt_open.disabled = not is_open
			opt_close.disabled = not is_open
			chk_split.disabled = not is_open
			s2_lbl.visible = is_split
			opt_s2_open.disabled = not is_split
			opt_s2_open.visible = is_split
			opt_s2_close.disabled = not is_split
			opt_s2_close.visible = is_split

		refresh_row_states.call()

		var save_row_changes = func(val = 0):
			refresh_row_states.call()
			var closed_val = 0 if chk_open.button_pressed else 1
			var split_val = 1 if (chk_split.button_pressed and chk_open.button_pressed) else 0
			var sel_open = opt_open.get_item_text(opt_open.selected)
			var sel_close = opt_close.get_item_text(opt_close.selected)
			var sel_s2_open = opt_s2_open.get_item_text(opt_s2_open.selected)
			var sel_s2_close = opt_s2_close.get_item_text(opt_s2_close.selected)
			sch_service.update_open_hours_atomic(id_val, sel_open, sel_close, closed_val, split_val, sel_s2_open, sel_s2_close)

		chk_open.toggled.connect(save_row_changes)
		chk_split.toggled.connect(save_row_changes)
		opt_open.item_selected.connect(save_row_changes)
		opt_close.item_selected.connect(save_row_changes)
		opt_s2_open.item_selected.connect(save_row_changes)
		opt_s2_close.item_selected.connect(save_row_changes)

		row_card.add_child(r_hbox)
		list_vbox.add_child(row_card)

	vbox.add_child(list_vbox)
	content_card.add_child(vbox)

func open_session_assistant_placeholder(session_data: Dictionary) -> void:
	_render_session_assistant_view(session_data)

func _render_session_assistant_view(session_data: Dictionary) -> void:
	content_card.get_children().map(func(c): c.queue_free())

	var sess_id = int(session_data.get("id", 0))
	var signups = sch_service.get_signups_for_session(sess_id) if sch_service else []

	var main_vbox = VBoxContainer.new(); main_vbox.add_theme_constant_override("separation", 16)

	# 1. HEADER PANEL
	var header_card = PanelContainer.new()
	var h_st = StyleBoxFlat.new()
	h_st.bg_color = Color(0.96, 0.98, 1.0, 1.0)
	h_st.border_width_left = 1; h_st.border_width_top = 1; h_st.border_width_right = 1; h_st.border_width_bottom = 1
	h_st.border_color = Color(0.85, 0.89, 0.94, 1.0)
	h_st.corner_radius_top_left = 8; h_st.corner_radius_top_right = 8; h_st.corner_radius_bottom_left = 8; h_st.corner_radius_bottom_right = 8
	h_st.content_margin_left = 16; h_st.content_margin_top = 16; h_st.content_margin_right = 16; h_st.content_margin_bottom = 16
	header_card.add_theme_stylebox_override("panel", h_st)

	var h_vbox = VBoxContainer.new(); h_vbox.add_theme_constant_override("separation", 10)

	var top_row = HBoxContainer.new(); top_row.add_theme_constant_override("separation", 12)
	var title_lbl = Label.new()
	title_lbl.text = "🚀 Session Assistant: " + str(session_data.get("title", "Session"))
	title_lbl.add_theme_font_size_override("font_size", 20); title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	top_row.add_child(title_lbl)

	var btn_msg = Button.new(); btn_msg.text = "✉️ Send Message"; btn_msg.custom_minimum_size = Vector2(130, 34); btn_msg.add_theme_font_size_override("font_size", 13)
	_style_outline_button(btn_msg)
	btn_msg.pressed.connect(func():
		open_session_communication_composer(session_data)
	)
	top_row.add_child(btn_msg)

	var btn_remind = Button.new(); btn_remind.text = "⏰ Reminder"; btn_remind.custom_minimum_size = Vector2(110, 34); btn_remind.add_theme_font_size_override("font_size", 13)
	_style_outline_button(btn_remind)
	btn_remind.pressed.connect(func():
		sch_service.send_session_reminder_atomic(sess_id, "confirmed", "SMS")
		_render_session_assistant_view(session_data)
	)
	top_row.add_child(btn_remind)

	var btn_csv = Button.new(); btn_csv.text = "📥 Export CSV"; btn_csv.custom_minimum_size = Vector2(110, 34); btn_csv.add_theme_font_size_override("font_size", 13)
	_style_outline_button(btn_csv)
	btn_csv.pressed.connect(func():
		var csv_data = sch_service.export_session_attendance_csv(sess_id)
		var path = "user://exports/session_attendance_" + str(sess_id) + ".csv"
	)
	top_row.add_child(btn_csv)

	var btn_edit = Button.new(); btn_edit.text = "✏️ Edit Session"; btn_edit.custom_minimum_size = Vector2(110, 34); btn_edit.add_theme_font_size_override("font_size", 13)
	_style_outline_button(btn_edit)
	btn_edit.pressed.connect(func(): open_session_editor_modal(session_data))
	top_row.add_child(btn_edit)

	var btn_return = Button.new(); btn_return.text = "⬅️ Return to Sessions"; btn_return.custom_minimum_size = Vector2(160, 34); btn_return.add_theme_font_size_override("font_size", 13)
	_style_primary_button(btn_return)
	btn_return.pressed.connect(func(): call_deferred("_refresh_tab_content"))
	top_row.add_child(btn_return)

	h_vbox.add_child(top_row)

	# Metadata Details Row
	var s_date = str(session_data.get("date_text", ""))
	var s_time = str(session_data.get("start_time", "")) + " - " + str(session_data.get("end_time", ""))
	var s_type = str(session_data.get("session_type_name", "General"))
	var s_uuid = str(session_data.get("session_uuid", ""))

	var conf_cnt = 0
	var wait_cnt = 0
	for s in signups:
		if str(s.get("signup_status")) == "confirmed": conf_cnt += 1
		elif str(s.get("signup_status")) == "waitlist": wait_cnt += 1

	var meta_lbl = Label.new()
	meta_lbl.text = "📅 " + s_date + " (" + s_time + ") • 🏷️ Type: " + s_type + " • 👥 Confirmed: " + str(conf_cnt) + " • ⏳ Waitlist: " + str(wait_cnt) + " • 🔑 ID: " + str(sess_id) + " (" + s_uuid + ")"
	meta_lbl.add_theme_font_size_override("font_size", 13); meta_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
	h_vbox.add_child(meta_lbl)

	header_card.add_child(h_vbox)
	main_vbox.add_child(header_card)

	# 2. PARTICIPANT SEARCH & REGISTRATION BAR
	var search_card = PanelContainer.new()
	var s_st = StyleBoxFlat.new(); s_st.bg_color = Color(0.98, 0.99, 1.0, 1.0); s_st.border_width_left = 1; s_st.border_width_top = 1; s_st.border_width_right = 1; s_st.border_width_bottom = 1
	s_st.border_color = Color(0.88, 0.91, 0.95, 1.0); s_st.corner_radius_top_left = 8; s_st.corner_radius_top_right = 8; s_st.corner_radius_bottom_left = 8; s_st.corner_radius_bottom_right = 8
	s_st.content_margin_left = 14; s_st.content_margin_top = 14; s_st.content_margin_right = 14; s_st.content_margin_bottom = 14
	search_card.add_theme_stylebox_override("panel", s_st)

	var svbox = VBoxContainer.new(); svbox.add_theme_constant_override("separation", 8)
	var shbox = HBoxContainer.new(); shbox.add_theme_constant_override("separation", 10)

	var search_input = LineEdit.new()
	search_input.placeholder_text = "🔍 Search Directory to Add Participant by Name or Member ID (e.g. ADM-101)..."
	search_input.custom_minimum_size = Vector2(400, 36); search_input.size_flags_horizontal = SIZE_EXPAND_FILL
	shbox.add_child(search_input)

	var btn_search = Button.new(); btn_search.text = "🔍 Lookup Person"; btn_search.custom_minimum_size = Vector2(140, 36)
	_style_outline_button(btn_search)
	shbox.add_child(btn_search)

	svbox.add_child(shbox)

	var search_results_vbox = VBoxContainer.new(); search_results_vbox.add_theme_constant_override("separation", 6)
	svbox.add_child(search_results_vbox)

	var do_search = func():
		search_results_vbox.get_children().map(func(c): c.queue_free())
		var query = search_input.text.strip_edges()
		if query == "": return
		var matches = sch_service.search_people_for_session_registration(query, sess_id) if sch_service else []
		if matches.size() == 0:
			var no_m = Label.new(); no_m.text = "No matching people found in directory."; no_m.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
			search_results_vbox.add_child(no_m)
			return

		for p in matches:
			var p_id = int(p.get("id"))
			var p_name = str(p.get("first_name")) + " " + str(p.get("last_name"))
			var p_human = str(p.get("human_id", ""))
			var is_reg = int(p.get("is_already_registered", 0)) == 1

			var p_row = HBoxContainer.new(); p_row.add_theme_constant_override("separation", 10)
			var p_lbl = Label.new(); p_lbl.text = "👤 " + p_name + " (" + p_human + ")"; p_lbl.add_theme_font_size_override("font_size", 13); p_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			p_row.add_child(p_lbl)

			if is_reg:
				var reg_lbl = Label.new(); reg_lbl.text = "✅ Already Registered (" + str(p.get("existing_status")).capitalize() + ")"; reg_lbl.add_theme_font_size_override("font_size", 12); reg_lbl.add_theme_color_override("font_color", Color(0.3, 0.6, 0.3, 1.0))
				p_row.add_child(reg_lbl)
			else:
				var btn_add = Button.new(); btn_add.text = "➕ Register Participant"; btn_add.custom_minimum_size = Vector2(160, 30)
				_style_outline_button(btn_add)
				btn_add.pressed.connect(func():
					sch_service.register_participant_atomic(sess_id, p_id)
					_render_session_assistant_view(session_data)
				)
				p_row.add_child(btn_add)

			search_results_vbox.add_child(p_row)

	btn_search.pressed.connect(do_search)
	search_input.text_submitted.connect(func(_t): do_search.call())

	search_card.add_child(svbox)
	main_vbox.add_child(search_card)

	# 3. SPLIT MAIN OPERATIONAL AREA (ROSTERS LEFT, ATTENDANCE RIGHT)
	var split_hbox = HBoxContainer.new(); split_hbox.add_theme_constant_override("separation", 16)

	# --- LEFT SIDE: CONFIRMED & WAITLIST ROSTERS ---
	var left_vbox = VBoxContainer.new(); left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL; left_vbox.add_theme_constant_override("separation", 16)

	# Confirmed Roster Card
	var conf_card = PanelContainer.new()
	var c_st = StyleBoxFlat.new(); c_st.bg_color = Color(1, 1, 1, 1); c_st.border_width_left = 1; c_st.border_width_top = 1; c_st.border_width_right = 1; c_st.border_width_bottom = 1
	c_st.border_color = Color(0.88, 0.91, 0.95, 1.0); c_st.corner_radius_top_left = 8; c_st.corner_radius_top_right = 8; c_st.corner_radius_bottom_left = 8; c_st.corner_radius_bottom_right = 8
	c_st.content_margin_left = 14; c_st.content_margin_top = 14; c_st.content_margin_right = 14; c_st.content_margin_bottom = 14
	conf_card.add_theme_stylebox_override("panel", c_st)

	var conf_vbox = VBoxContainer.new(); conf_vbox.add_theme_constant_override("separation", 10)
	var conf_title = Label.new(); conf_title.text = "👥 Confirmed Participants Roster (" + str(conf_cnt) + ")"; conf_title.add_theme_font_size_override("font_size", 16); conf_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	conf_vbox.add_child(conf_title)

	var confirmed_list = []
	var waitlist_list = []
	for s in signups:
		if str(s.get("signup_status")) == "confirmed": confirmed_list.append(s)
		elif str(s.get("signup_status")) == "waitlist": waitlist_list.append(s)

	if confirmed_list.size() > 0:
		for s in confirmed_list:
			var s_id_val = int(s.get("id"))
			var fn = str(s.get("first_name")) if s.get("first_name") != null else ""
			var ln = str(s.get("last_name")) if s.get("last_name") != null else ""
			var p_name = (fn + " " + ln).strip_edges()
			var p_human = str(s.get("human_id", ""))
			var att_status = str(s.get("attendance_status", "unmarked"))
			var comm_needed = int(s.get("communication_needed", 0)) == 1

			var crow = HBoxContainer.new(); crow.add_theme_constant_override("separation", 10)
			var clbl = Label.new(); clbl.text = "👤 " + p_name + " (" + p_human + ")"; clbl.add_theme_font_size_override("font_size", 13); clbl.size_flags_horizontal = SIZE_EXPAND_FILL
			crow.add_child(clbl)

			if comm_needed:
				var cbadge = Label.new(); cbadge.text = "✉️ Comm Needed"; cbadge.add_theme_font_size_override("font_size", 11); cbadge.add_theme_color_override("font_color", Color(0.85, 0.45, 0.1, 1.0))
				crow.add_child(cbadge)

			var btn_rem = Button.new(); btn_rem.text = "🗑️ Remove"; btn_rem.custom_minimum_size = Vector2(80, 28)
			_style_outline_button(btn_rem)
			btn_rem.pressed.connect(func():
				# Trigger removal dialog or default remove + auto-promote
				sch_service.remove_confirmed_and_autopromote_atomic(sess_id, s_id_val)
				_render_session_assistant_view(session_data)
			)
			crow.add_child(btn_rem)

			conf_vbox.add_child(crow)
	else:
		var empty_c = Label.new(); empty_c.text = "No confirmed participants currently registered."; empty_c.add_theme_font_size_override("font_size", 13); empty_c.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		conf_vbox.add_child(empty_c)

	conf_card.add_child(conf_vbox)
	left_vbox.add_child(conf_card)

	# Waitlist Roster Card
	var wait_card = PanelContainer.new()
	var w_st = StyleBoxFlat.new(); w_st.bg_color = Color(1, 1, 1, 1); w_st.border_width_left = 1; w_st.border_width_top = 1; w_st.border_width_right = 1; w_st.border_width_bottom = 1
	w_st.border_color = Color(0.88, 0.91, 0.95, 1.0); w_st.corner_radius_top_left = 8; w_st.corner_radius_top_right = 8; w_st.corner_radius_bottom_left = 8; w_st.corner_radius_bottom_right = 8
	w_st.content_margin_left = 14; w_st.content_margin_top = 14; w_st.content_margin_right = 14; w_st.content_margin_bottom = 14
	wait_card.add_theme_stylebox_override("panel", w_st)

	var wait_vbox = VBoxContainer.new(); wait_vbox.add_theme_constant_override("separation", 10)
	var wait_title = Label.new(); wait_title.text = "⏳ Waiting List Priority Queue (" + str(wait_cnt) + ")"; wait_title.add_theme_font_size_override("font_size", 16); wait_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	wait_vbox.add_child(wait_title)

	if waitlist_list.size() > 0:
		for idx in range(waitlist_list.size()):
			var s = waitlist_list[idx]
			var s_id_val = int(s.get("id"))
			var s_uuid_val = str(s.get("signup_uuid", ""))
			var pos_val = int(s.get("position", idx + 1))
			var fn = str(s.get("first_name")) if s.get("first_name") != null else ""
			var ln = str(s.get("last_name")) if s.get("last_name") != null else ""
			var p_name = (fn + " " + ln).strip_edges()
			var p_human = str(s.get("human_id", ""))

			var wrow = HBoxContainer.new(); wrow.add_theme_constant_override("separation", 8)
			var wlbl = Label.new(); wlbl.text = "#" + str(pos_val) + " ⏳ " + p_name + " (" + p_human + ")"; wlbl.add_theme_font_size_override("font_size", 13); wlbl.size_flags_horizontal = SIZE_EXPAND_FILL
			wrow.add_child(wlbl)

			var btn_prom = Button.new(); btn_prom.text = "⚡ Promote"; btn_prom.custom_minimum_size = Vector2(80, 28)
			_style_outline_button(btn_prom)
			btn_prom.pressed.connect(func():
				sch_service.promote_waitlist_atomic(s_uuid_val)
				_render_session_assistant_view(session_data)
			)
			wrow.add_child(btn_prom)

			var btn_up = Button.new(); btn_up.text = "⬆️"; btn_up.custom_minimum_size = Vector2(36, 28)
			_style_outline_button(btn_up)
			btn_up.pressed.connect(func():
				sch_service.move_waitlist_position_atomic(sess_id, s_id_val, "up")
				_render_session_assistant_view(session_data)
			)
			wrow.add_child(btn_up)

			var btn_dn = Button.new(); btn_dn.text = "⬇️"; btn_dn.custom_minimum_size = Vector2(36, 28)
			_style_outline_button(btn_dn)
			btn_dn.pressed.connect(func():
				sch_service.move_waitlist_position_atomic(sess_id, s_id_val, "down")
				_render_session_assistant_view(session_data)
			)
			wrow.add_child(btn_dn)

			var btn_wrem = Button.new(); btn_wrem.text = "🗑️"; btn_wrem.custom_minimum_size = Vector2(36, 28)
			_style_outline_button(btn_wrem)
			btn_wrem.pressed.connect(func():
				sch_service.remove_waitlist_participant_atomic(sess_id, s_id_val)
				_render_session_assistant_view(session_data)
			)
			wrow.add_child(btn_wrem)

			wait_vbox.add_child(wrow)
	else:
		var empty_w = Label.new(); empty_w.text = "No students currently on waitlist queue."; empty_w.add_theme_font_size_override("font_size", 13); empty_w.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		wait_vbox.add_child(empty_w)

	wait_card.add_child(wait_vbox)
	left_vbox.add_child(wait_card)

	split_hbox.add_child(left_vbox)

	# --- RIGHT SIDE: ATTENDANCE SUMMARY & CHECKLIST ---
	var right_vbox = VBoxContainer.new(); right_vbox.custom_minimum_size = Vector2(380, 0); right_vbox.add_theme_constant_override("separation", 16)

	var att_card = PanelContainer.new()
	var a_st = StyleBoxFlat.new(); a_st.bg_color = Color(1, 1, 1, 1); a_st.border_width_left = 1; a_st.border_width_top = 1; a_st.border_width_right = 1; a_st.border_width_bottom = 1
	a_st.border_color = Color(0.88, 0.91, 0.95, 1.0); a_st.corner_radius_top_left = 8; a_st.corner_radius_top_right = 8; a_st.corner_radius_bottom_left = 8; a_st.corner_radius_bottom_right = 8
	a_st.content_margin_left = 14; a_st.content_margin_top = 14; a_st.content_margin_right = 14; a_st.content_margin_bottom = 14
	att_card.add_theme_stylebox_override("panel", a_st)

	var att_vbox = VBoxContainer.new(); att_vbox.add_theme_constant_override("separation", 10)
	var att_title = Label.new(); att_title.text = "📋 Session Attendance Checklist"; att_title.add_theme_font_size_override("font_size", 16); att_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	att_vbox.add_child(att_title)

	var pres_cnt = 0
	var noshow_cnt = 0
	var unmark_cnt = 0
	for s in confirmed_list:
		var st_val = str(s.get("attendance_status", "unmarked"))
		if st_val == "present": pres_cnt += 1
		elif st_val == "no_show": noshow_cnt += 1
		else: unmark_cnt += 1

	var att_summary_lbl = Label.new()
	att_summary_lbl.text = "Confirmed: " + str(confirmed_list.size()) + " • ✅ Present: " + str(pres_cnt) + " • ❌ No Show: " + str(noshow_cnt) + " • ⚪ Unmarked: " + str(unmark_cnt)
	att_summary_lbl.add_theme_font_size_override("font_size", 12); att_summary_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
	att_vbox.add_child(att_summary_lbl)

	if confirmed_list.size() > 0:
		for s in confirmed_list:
			var p_id_val = int(s.get("person_id"))
			var fn = str(s.get("first_name")) if s.get("first_name") != null else ""
			var ln = str(s.get("last_name")) if s.get("last_name") != null else ""
			var p_name = (fn + " " + ln).strip_edges()
			var att_st = str(s.get("attendance_status", "unmarked"))

			var arow = HBoxContainer.new(); arow.add_theme_constant_override("separation", 6)
			var albl = Label.new()
			var badge_icon = "⚪ "
			if att_st == "present": badge_icon = "✅ "
			elif att_st == "no_show": badge_icon = "❌ "
			albl.text = badge_icon + p_name; albl.add_theme_font_size_override("font_size", 13); albl.size_flags_horizontal = SIZE_EXPAND_FILL
			arow.add_child(albl)

			var btn_p = Button.new(); btn_p.text = "Present"; btn_p.custom_minimum_size = Vector2(65, 26)
			_style_outline_button(btn_p)
			btn_p.pressed.connect(func():
				sch_service.mark_session_attendance_atomic(sess_id, p_id_val, "present")
				_render_session_assistant_view(session_data)
			)
			arow.add_child(btn_p)

			var btn_ns = Button.new(); btn_ns.text = "No Show"; btn_ns.custom_minimum_size = Vector2(68, 26)
			_style_outline_button(btn_ns)
			btn_ns.pressed.connect(func():
				sch_service.mark_session_attendance_atomic(sess_id, p_id_val, "no_show")
				_render_session_assistant_view(session_data)
			)
			arow.add_child(btn_ns)

			var btn_un = Button.new(); btn_un.text = "Clear"; btn_un.custom_minimum_size = Vector2(50, 26)
			_style_outline_button(btn_un)
			btn_un.pressed.connect(func():
				sch_service.mark_session_attendance_atomic(sess_id, p_id_val, "unmarked")
				_render_session_assistant_view(session_data)
			)
			arow.add_child(btn_un)

			att_vbox.add_child(arow)
	else:
		var empty_a = Label.new(); empty_a.text = "No confirmed participants to mark attendance."; empty_a.add_theme_font_size_override("font_size", 13); empty_a.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		att_vbox.add_child(empty_a)

	att_card.add_child(att_vbox)
	right_vbox.add_child(att_card)

	split_hbox.add_child(right_vbox)
	main_vbox.add_child(split_hbox)

	content_card.add_child(main_vbox)

func _get_current_week_range_string() -> String:
	var start_d = get_date_string_for_day_index(0)
	var end_d = get_date_string_for_day_index(6)
	return _format_date_for_range(start_d) + " — " + _format_date_for_range(end_d)

func _format_date_for_range(date_str: String) -> String:
	var parts = date_str.split("-")
	if parts.size() != 3: return date_str
	var year = parts[0]
	var month_int = int(parts[1])
	var day = str(int(parts[2]))
	var months = [
		"", "Jan", "Feb", "Mar", "Apr", "May", "Jun", 
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
	]
	var month_name = months[month_int] if (month_int >= 1 and month_int <= 12) else parts[1]
	return month_name + " " + day + ", " + year

func _format_short_date(date_str: String) -> String:
	var parts = date_str.split("-")
	if parts.size() != 3: return date_str
	return str(int(parts[1])) + "/" + str(int(parts[2]))

# ==================== HELPER CLASSES: SHIFT CARD & DAY COLUMN ====================

class ShiftCardControl extends PanelContainer:
	var shift_data: Dictionary
	var is_selected: bool
	var is_pending_cut: bool
	var main_view: Control

	func _init(data: Dictionary, selected: bool, pending_cut: bool, view: Control) -> void:
		shift_data = data
		is_selected = selected
		is_pending_cut = pending_cut
		main_view = view
		custom_minimum_size = Vector2(0, 56)

		var st = StyleBoxFlat.new()
		if is_pending_cut:
			st.bg_color = Color(0.96, 0.96, 0.96, 0.5)
			st.border_width_left = 3; st.border_color = Color(0.60, 0.68, 0.78, 0.5)
		elif is_selected:
			st.bg_color = Color(0.92, 0.96, 1.0, 1.0)
			st.border_width_left = 4; st.border_color = Color(0.88, 0.35, 0.21, 1.0)
		else:
			st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
			st.border_width_left = 3; st.border_color = Color(0.88, 0.35, 0.21, 1.0)

		st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
		st.content_margin_left = 8; st.content_margin_top = 6; st.content_margin_right = 8; st.content_margin_bottom = 6
		add_theme_stylebox_override("panel", st)

		var ivbox = VBoxContainer.new()
		ivbox.add_theme_constant_override("separation", 2)

		var start_t = str(shift_data.get("start_time", ""))
		var end_t = str(shift_data.get("end_time", ""))
		var time_str = start_t + " - " + end_t if (start_t != "" and end_t != "") else ""

		var name = str(shift_data.get("person_name", ""))
		var role = str(shift_data.get("shift_role", "Staff"))
		var area = str(shift_data.get("area", "Study Center"))
		if area == "" or area == "null": area = "Study Center"

		var prefix = "✂️ " if is_pending_cut else ("☑️ " if is_selected else "")

		# 1. Operating Hours
		if not time_str.is_empty():
			var t_lbl = Label.new()
			t_lbl.text = "🕒 " + time_str
			t_lbl.add_theme_font_size_override("font_size", 12)
			t_lbl.add_theme_color_override("font_color", Color(0.12, 0.45, 0.22, 1.0))
			ivbox.add_child(t_lbl)

		# 2. Person
		var n_lbl = Label.new()
		n_lbl.text = prefix + "👤 " + name
		n_lbl.add_theme_font_size_override("font_size", 14)
		n_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
		ivbox.add_child(n_lbl)

		# 3. Staff Classification
		var r_lbl = Label.new()
		r_lbl.text = role
		r_lbl.add_theme_font_size_override("font_size", 12)
		r_lbl.add_theme_color_override("font_color", Color(0.40, 0.46, 0.54, 1.0))
		ivbox.add_child(r_lbl)

		# 4. Study Center (Area)
		var a_lbl = Label.new()
		a_lbl.text = area
		a_lbl.add_theme_font_size_override("font_size", 11)
		a_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68, 1.0))
		ivbox.add_child(a_lbl)

		add_child(ivbox)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var mb = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				main_view.open_shift_context_menu(shift_data, mb.global_position)
			elif mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
				main_view.open_shift_modal(shift_data)

class DayColumnControl extends PanelContainer:
	var day_code: String
	var day_index: int
	var is_target_day: bool
	var main_view: Control

	func _init(code: String, idx: int, target: bool, view: Control) -> void:
		day_code = code
		day_index = idx
		is_target_day = target
		main_view = view

		var st = StyleBoxFlat.new()
		st.bg_color = Color(1.0, 0.97, 0.95, 1.0) if is_target_day else Color(0.96, 0.97, 0.99, 1.0)
		st.border_width_left = 2 if is_target_day else 1
		st.border_width_top = 2 if is_target_day else 1
		st.border_width_right = 2 if is_target_day else 1
		st.border_width_bottom = 2 if is_target_day else 1
		st.border_color = Color(0.88, 0.35, 0.21, 1.0) if is_target_day else Color(0.88, 0.91, 0.95, 1.0)
		st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
		st.content_margin_left = 6; st.content_margin_top = 8; st.content_margin_right = 6; st.content_margin_bottom = 8
		add_theme_stylebox_override("panel", st)
