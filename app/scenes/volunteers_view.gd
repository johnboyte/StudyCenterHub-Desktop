extends "res://app/scenes/standard_page_container.gd"

## Volunteers & Shift Roster Controller (VOL-SPR1-001)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const VolunteersServiceScript = preload("res://src/domain/volunteers/volunteers_service.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			vol_service = VolunteersServiceScript.new(db)
			_populate_dropdowns()
			_refresh_shift_log()

var vol_service: RefCounted
var volunteer_list: Array = []
var session_list: Array = []

@onready var volunteer_dropdown: OptionButton = $MarginContainer/MainVBox/AssignCard/AssignMargin/AssignVBox/SelectHBox/VolunteerDropdown
@onready var session_dropdown: OptionButton = $MarginContainer/MainVBox/AssignCard/AssignMargin/AssignVBox/SelectHBox/SessionDropdown
@onready var role_dropdown: OptionButton = $MarginContainer/MainVBox/AssignCard/AssignMargin/AssignVBox/ActionHBox/RoleDropdown
@onready var btn_assign_shift: Button = $MarginContainer/MainVBox/AssignCard/AssignMargin/AssignVBox/ActionHBox/BtnAssignShift
@onready var shift_log_card: PanelContainer = $MarginContainer/MainVBox/ShiftLogCard

func _ready() -> void:
	_init_database()
	_style_card()
	_populate_dropdowns()
	_connect_signals()
	_refresh_shift_log()

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig = MigrationsRunnerScript.new(db)
		mig.run_migrations()
	if not vol_service:
		vol_service = VolunteersServiceScript.new(db)

func _style_card() -> void:
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
	shift_log_card.add_theme_stylebox_override("panel", style)

	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = _get_active_theme_color()
	btn_st.corner_radius_top_left = 6
	btn_st.corner_radius_top_right = 6
	btn_st.corner_radius_bottom_left = 6
	btn_st.corner_radius_bottom_right = 6
	btn_assign_shift.add_theme_stylebox_override("normal", btn_st)
	btn_assign_shift.add_theme_stylebox_override("hover", btn_st)
	btn_assign_shift.add_theme_stylebox_override("pressed", btn_st)

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

func _populate_dropdowns() -> void:
	if not db: return
	if not vol_service: vol_service = VolunteersServiceScript.new(db)

	# 1. Volunteer Dropdown
	volunteer_dropdown.clear()
	volunteer_list = vol_service.get_volunteers()
	for i in range(volunteer_list.size()):
		var v = volunteer_list[i]
		var name = str(v.get("first_name")) + " " + str(v.get("last_name")) + " (" + str(v.get("human_id")) + ")"
		volunteer_dropdown.add_item(name, i)

	# 2. Session Dropdown
	session_dropdown.clear()
	session_list.clear()
	var s_res = db.execute("SELECT id, title, room_location FROM sessions ORDER BY title ASC;")
	if s_res["success"] and s_res["data"].size() > 0:
		session_list = s_res["data"]
		for i in range(session_list.size()):
			var s = session_list[i]
			var name = str(s.get("title")) + " | " + str(s.get("room_location"))
			session_dropdown.add_item(name, i)
	else:
		session_dropdown.add_item("Bible Study - Adults | Fellowship Hall", 0)

	# 3. Role Dropdown
	role_dropdown.clear()
	role_dropdown.add_item("Lead Tutor", 0)
	role_dropdown.add_item("Check-In Host", 1)
	role_dropdown.add_item("Youth Supervisor", 2)
	role_dropdown.add_item("AV Tech", 3)

func _connect_signals() -> void:
	if btn_assign_shift:
		btn_assign_shift.pressed.connect(_on_assign_shift_pressed)

func _on_assign_shift_pressed() -> void:
	if volunteer_list.size() == 0: return

	var sel_v_idx = volunteer_dropdown.selected
	if sel_v_idx < 0 or sel_v_idx >= volunteer_list.size(): return
	var person = volunteer_list[sel_v_idx]

	var session_id = 1
	if session_list.size() > 0:
		var sel_s_idx = session_dropdown.selected
		if sel_s_idx >= 0 and sel_s_idx < session_list.size():
			session_id = int(session_list[sel_s_idx].get("id", 1))

	var shift_role = role_dropdown.get_item_text(role_dropdown.selected)

	var res = vol_service.assign_shift_atomic(person, session_id, shift_role)
	if res["success"]:
		print("Volunteer shift assigned successfully: ", res["shift_uuid"])
		_refresh_shift_log()

func _refresh_shift_log() -> void:
	if not db: return
	if not vol_service: vol_service = VolunteersServiceScript.new(db)

	for child in shift_log_card.get_children():
		child.free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title_lbl = Label.new()
	title_lbl.text = "Active Volunteer Shift Roster"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_lbl)

	var shifts = vol_service.get_recent_shifts()
	if shifts.size() > 0:
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 360)
		scroll.size_flags_vertical = SIZE_EXPAND_FILL

		var list_vbox = VBoxContainer.new()
		list_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		list_vbox.add_theme_constant_override("separation", 8)

		for item in shifts:
			var first = str(item.get("first_name")) if item.get("first_name") != null else ""
			var last = str(item.get("last_name")) if item.get("last_name") != null else ""
			var name = (first + " " + last).strip_edges()
			if name == "": name = str(item.get("human_id")) if item.get("human_id") != null else "Volunteer"

			var role = str(item.get("shift_role", "Lead Tutor"))
			var sess = str(item.get("session_title")) if item.get("session_title") != null else "General Study Session"
			var time_s = str(item.get("assigned_at", ""))

			var row = Label.new()
			row.text = "  🤝 " + name + " • Role: " + role + " | Session: " + sess + " [" + time_s + "]"
			row.add_theme_font_size_override("font_size", 13)
			row.add_theme_color_override("font_color", Color(0.22, 0.28, 0.36, 1.0))
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list_vbox.add_child(row)

		scroll.add_child(list_vbox)
		vbox.add_child(scroll)
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "No volunteer shifts assigned today. Use the control panel above to assign a volunteer."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(empty_lbl)

	shift_log_card.add_child(vbox)
