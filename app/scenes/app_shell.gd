extends Control

## StudyCenterHub Desktop Main Application Shell (SHELL-SPR1-001)
## Complies with [PD-001] (Offline Storage), [PD-002] (Read Isolation), and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const GatewaySyncScript = preload("res://src/domain/sync/gateway_sync_service.gd")
const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")

const HomeViewScript = preload("res://app/scenes/home_view.gd")
const DirectoryViewScript = preload("res://app/scenes/directory_view.gd")

var db: RefCounted
var read_service: RefCounted
var current_view_name: String = "home"
var current_view_node: Node = null
var btn_nav_kiosk: Button


@onready var sidebar_panel: PanelContainer = $SidebarPanel
@onready var btn_nav_home: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavHome
@onready var btn_nav_people: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavPeople
@onready var btn_nav_communications: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavCommunications
@onready var btn_nav_attendance: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavAttendance
@onready var btn_nav_schedules: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavSchedules
@onready var btn_nav_volunteers: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavVolunteers
@onready var btn_nav_pathways: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavPathways
@onready var btn_nav_administration: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavAdministration
@onready var btn_nav_reports: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavReports
@onready var btn_nav_settings: Button = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox/BtnNavSettings

@onready var top_header_bar: PanelContainer = $TopHeaderBar
@onready var greeting_label: Label = $TopHeaderBar/TopMargin/TopHBox/GreetingVBox/GreetingLabel
@onready var greeting_subtitle: Label = $TopHeaderBar/TopMargin/TopHBox/GreetingVBox/GreetingSubtitle
@onready var team_leader_dropdown: OptionButton = $TopHeaderBar/TopMargin/TopHBox/TeamLeaderHBox/TeamLeaderDropdown
@onready var date_pill: Label = $TopHeaderBar/TopMargin/TopHBox/DatePill
@onready var weather_pill: Label = $TopHeaderBar/TopMargin/TopHBox/WeatherPill
@onready var page_scroll: ScrollContainer = $ContentArea/PageScroll
@onready var page_container: MarginContainer = $ContentArea/PageScroll/StandardPageContainer
@onready var content_container: PanelContainer = $ContentArea/PageScroll/StandardPageContainer/ContentContainer
@onready var content_area: PanelContainer = $ContentArea

const DEFAULT_SUBTITLES: Dictionary = {
	"home": "Here’s what’s happening at StudyCenter today.",
	"people": "Find, update, and manage constituent records.",
	"communications": "Create, schedule, and review messages.",
	"attendance": "Scan badges, find people, and record attendance.",
	"schedules": "Coordinate staffing, sessions, volunteers, and operating hours.",
	"volunteers": "Manage volunteer availability, assignments, and service.",
	"pathways": "Review participant progress, follow-up, and next steps.",
	"administration": "Manage users, permissions, integrations, and organization settings.",
	"reports": "Review attendance, engagement, and ministry activity.",
	"settings": "Customize your StudyCenter experience and preferences."
}

var _sync_timer: Timer
var _is_syncing: bool = false

func _ready() -> void:
	add_to_group("app_shell")
	_init_database()
	_apply_pd008_theme_styles()
	_populate_team_leaders()
	_connect_nav_signals()
	top_header_bar.resized.connect(_adjust_content_area_offset)
	_adjust_content_area_offset()
	switch_view("home")
	_start_auto_sync()

func _start_auto_sync() -> void:
	_sync_timer = Timer.new()
	_sync_timer.wait_time = 30.0
	_sync_timer.autostart = true
	_sync_timer.one_shot = false
	_sync_timer.timeout.connect(_on_sync_timer_tick)
	add_child(_sync_timer)
	# Run first sync immediately after startup
	call_deferred("_on_sync_timer_tick")

func _on_sync_timer_tick() -> void:
	if _is_syncing or not db:
		return
	_is_syncing = true
	print("[AutoSync] Pulling events from relay...")
	var sync_svc = GatewaySyncScript.new(db, self)
	sync_svc.sync_now(func(result: Dictionary):
		var inserted = result.get("inserted_count", 0)
		if inserted > 0:
			print("[AutoSync] Pulled ", inserted, " new events. Processing...")
			var processor = InboundEventProcessorScript.new(db, self)
			processor.process_pending_events(func(proc_result: Dictionary):
				print("[AutoSync] Processed ", proc_result.get("processed_count", 0), " events.")
				_is_syncing = false
			)
		else:
			_is_syncing = false
	)

func _adjust_content_area_offset() -> void:
	if not is_inside_tree() or not top_header_bar or not content_area:
		return
	content_area.offset_top = top_header_bar.size.y

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig_runner = MigrationsRunnerScript.new(db)
		mig_runner.run_migrations()
	if not read_service:
		read_service = DirectoryReadServiceScript.new(db)

func _apply_pd008_theme_styles() -> void:
	var active_color = _get_active_theme_color()

	# 1. Left Sidebar Style (Deep Navy #1E2430 with active accent border)
	var sb_style = StyleBoxFlat.new()
	sb_style.bg_color = Color(0.12, 0.14, 0.19, 1.0)
	sb_style.border_width_right = 2
	sb_style.border_color = active_color
	sidebar_panel.add_theme_stylebox_override("panel", sb_style)

	# 2. Top Header Bar Style (Subtle distinct background with active accent border and shadow)
	var th_style = StyleBoxFlat.new()
	th_style.bg_color = Color(0.945, 0.953, 0.965, 1.0) # Light-gray #F1F3F6
	th_style.border_width_bottom = 3
	th_style.border_color = active_color
	th_style.shadow_color = Color(0, 0, 0, 0.12) # Clear soft shadow
	th_style.shadow_size = 6
	th_style.shadow_offset = Vector2(0, 3)
	top_header_bar.add_theme_stylebox_override("panel", th_style)

	# 3. Main Content Container Style (App Background Theme) - Standardized to Solid White
	var main_bg_style = StyleBoxFlat.new()
	main_bg_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	content_area.add_theme_stylebox_override("panel", main_bg_style)

	var trans_style = StyleBoxEmpty.new()
	content_container.add_theme_stylebox_override("panel", trans_style)

	# Dynamic Environment Label
	var env = OS.get_environment("STUDYCENTERHUB_ENV").to_lower().strip_edges()
	if env == "":
		env = "development"

	var env_label = Label.new()
	env_label.text = env.to_upper()
	env_label.add_theme_font_size_override("font_size", 12)
	env_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	env_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	env_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var env_badge = PanelContainer.new()
	env_badge.size_flags_vertical = SIZE_SHRINK_CENTER
	var badge_st = StyleBoxFlat.new()
	badge_st.corner_radius_top_left = 6
	badge_st.corner_radius_top_right = 6
	badge_st.corner_radius_bottom_left = 6
	badge_st.corner_radius_bottom_right = 6
	badge_st.content_margin_left = 10
	badge_st.content_margin_top = 4
	badge_st.content_margin_right = 10
	badge_st.content_margin_bottom = 4

	if env == "production":
		badge_st.bg_color = Color(0.18, 0.49, 0.35, 1.0) # Forest Green #2E7D56
	elif env == "staging":
		badge_st.bg_color = Color(0.88, 0.55, 0.11, 1.0) # Warm Amber/Orange #DF8C1B
	else:
		badge_st.bg_color = Color(0.20, 0.38, 0.65, 1.0) # Professional Blue #3461A6

	env_badge.add_theme_stylebox_override("panel", badge_st)
	env_badge.add_child(env_label)

	var top_hbox = $TopHeaderBar/TopMargin/TopHBox
	top_hbox.add_child(env_badge)
	top_hbox.move_child(env_badge, 1) # Position right after GreetingVBox

func _populate_team_leaders() -> void:
	if not team_leader_dropdown: return
	team_leader_dropdown.clear()

	db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL, updated_at TEXT NOT NULL DEFAULT (datetime('now')));")

	var staff_list = ["John Boyte", "Sarah Johnson", "Michael Brown", "Emily Davis"]

	var p_res = db.execute("SELECT first_name, last_name FROM people ORDER BY last_name ASC, first_name ASC;")
	if p_res["success"] and p_res["data"].size() > 0:
		var db_staff = []
		for r in p_res["data"]:
			var name = (String(r.get("first_name", "")) + " " + String(r.get("last_name", ""))).strip_edges()
			if name != "" and not name in db_staff:
				db_staff.append(name)
		if db_staff.size() > 0:
			staff_list = db_staff

	var active_leader = "John Boyte"
	var app_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ACTIVE_SUPERVISOR' LIMIT 1;")
	if app_res["success"] and app_res["data"].size() > 0:
		active_leader = app_res["data"][0].get("setting_value", "John Boyte")

	var sel_index = 0
	for i in range(staff_list.size()):
		var name = staff_list[i]
		team_leader_dropdown.add_item(name, i)
		if name == active_leader:
			sel_index = i

	team_leader_dropdown.select(sel_index)
	_update_header_for_current_view(staff_list[sel_index] if staff_list.size() > sel_index else "John")

	if not team_leader_dropdown.item_selected.is_connected(_on_team_leader_selected):
		team_leader_dropdown.item_selected.connect(_on_team_leader_selected)

func _on_team_leader_selected(index: int) -> void:
	var name = team_leader_dropdown.get_item_text(index)
	_update_header_for_current_view(name.split(" ")[0])

	db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL);")
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('ACTIVE_SUPERVISOR', ?);", [name])

func _update_header_for_current_view(first_name: String = "") -> void:
	if first_name == "":
		if team_leader_dropdown and team_leader_dropdown.selected >= 0:
			first_name = team_leader_dropdown.get_item_text(team_leader_dropdown.selected).split(" ")[0]
		else:
			first_name = "John"

	var time_dict = Time.get_time_dict_from_system()
	var hour = int(time_dict.get("hour", 9))
	var salutation = "Good morning"
	if hour >= 12 and hour < 17:
		salutation = "Good afternoon"
	elif hour >= 17:
		salutation = "Good evening"

	# Check active user birthday on Home page
	var is_bday = false
	if current_view_name == "home" and db:
		var date_dict = Time.get_date_dict_from_system()
		var cur_m = int(date_dict.get("month", 1))
		var cur_d = int(date_dict.get("day", 1))

		var p_res = db.execute("SELECT birth_month, birth_day FROM people WHERE first_name = ? LIMIT 1;", [first_name])
		if p_res["success"] and p_res["data"].size() > 0:
			var bm = p_res["data"][0].get("birth_month")
			var bd = p_res["data"][0].get("birth_day")
			if bm != null and bd != null and int(bm) == cur_m and int(bd) == cur_d:
				is_bday = true

	if is_bday:
		if greeting_label:
			greeting_label.text = "Happy Birthday, " + first_name + "!"
		if greeting_subtitle:
			greeting_subtitle.text = "We hope your day is filled with joy. Thank you for all you do at StudyCenter!"
			greeting_subtitle.tooltip_text = greeting_subtitle.text
		return

	if greeting_label:
		greeting_label.text = salutation + ", " + first_name + "!"

	# Resolve subtitle: 1. User Override -> 2. Org Default -> 3. Hardcoded Fallback
	var sub_text = _resolve_page_subtitle(current_view_name)
	if greeting_subtitle:
		greeting_subtitle.text = sub_text
		greeting_subtitle.tooltip_text = sub_text

func _resolve_page_subtitle(page_key: String) -> String:
	if not db:
		return DEFAULT_SUBTITLES.get(page_key, "StudyCenter Operations Subsystem")

	# Check User-Specific Override
	var u_res = db.execute("SELECT message FROM user_page_header_messages WHERE page_key = ? LIMIT 1;", [page_key])
	if u_res["success"] and u_res["data"].size() > 0:
		var msg = String(u_res["data"][0].get("message", "")).strip_edges()
		if msg != "":
			return msg

	# Check Organization-Wide Default
	var o_res = db.execute("SELECT message FROM organization_page_header_messages WHERE page_key = ? LIMIT 1;", [page_key])
	if o_res["success"] and o_res["data"].size() > 0:
		var msg = String(o_res["data"][0].get("message", "")).strip_edges()
		if msg != "":
			return msg

	return DEFAULT_SUBTITLES.get(page_key, "StudyCenter Operations Subsystem")

func _connect_nav_signals() -> void:
	if btn_nav_home: btn_nav_home.pressed.connect(func(): switch_view("home"))
	if btn_nav_people: btn_nav_people.pressed.connect(func(): switch_view("people"))
	if btn_nav_communications: btn_nav_communications.pressed.connect(func(): switch_view("communications"))
	if btn_nav_attendance: btn_nav_attendance.pressed.connect(func(): switch_view("attendance"))
	if btn_nav_schedules: btn_nav_schedules.pressed.connect(func(): switch_view("schedules"))
	if btn_nav_volunteers: btn_nav_volunteers.pressed.connect(func(): switch_view("volunteers"))
	if btn_nav_pathways: btn_nav_pathways.pressed.connect(func(): switch_view("pathways"))
	if btn_nav_administration: btn_nav_administration.pressed.connect(func(): switch_view("administration"))
	if btn_nav_reports: btn_nav_reports.pressed.connect(func(): switch_view("reports"))
	if btn_nav_settings: btn_nav_settings.pressed.connect(func(): switch_view("settings"))

	# Dynamically create Kiosk Mode nav button
	btn_nav_kiosk = Button.new()
	btn_nav_kiosk.name = "BtnNavKiosk"
	btn_nav_kiosk.custom_minimum_size = Vector2(0, 44)
	if btn_nav_settings:
		btn_nav_kiosk.add_theme_font_size_override("font_size", 16)
	btn_nav_kiosk.text = "  🖥️   Kiosk Mode"
	btn_nav_kiosk.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn_nav_kiosk.pressed.connect(func(): switch_view("kiosk"))

	var nav_vbox = $SidebarPanel/SidebarMargin/SidebarVBox/NavScroll/NavVBox
	nav_vbox.add_child(btn_nav_kiosk)

func switch_view(view_name: String, params: Dictionary = {}) -> bool:
	if view_name.is_empty():
		return false

	current_view_name = view_name

	if view_name == "kiosk":
		if sidebar_panel: sidebar_panel.visible = false
		if top_header_bar: top_header_bar.visible = false
		if page_scroll: page_scroll.visible = false
		if content_area:
			content_area.offset_left = 0
			content_area.offset_top = 0
	else:
		if sidebar_panel: sidebar_panel.visible = true
		if top_header_bar: top_header_bar.visible = true
		if page_scroll: page_scroll.visible = true
		if content_area:
			content_area.offset_left = 260.0
			_adjust_content_area_offset()

	_update_nav_button_styles()
	_update_header_for_current_view()

	# Clear previous view nodes from both standard and overlay layouts
	if content_container:
		for child in content_container.get_children():
			content_container.remove_child(child)
			child.queue_free()
	if content_area:
		for child in content_area.get_children():
			if child != page_scroll:
				content_area.remove_child(child)
				child.queue_free()

	if view_name == "home":
		var scene_res = load("res://app/scenes/home_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if current_view_node.has_method("set_app_shell"):
				current_view_node.set_app_shell(self)
	elif view_name == "people":
		var scene_res = load("res://app/scenes/directory_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
			if "read_service" in current_view_node:
				current_view_node.read_service = read_service
	elif view_name == "administration":
		var scene_res = load("res://app/scenes/administration_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "communications":
		var scene_res = load("res://app/scenes/communications_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "schedules":
		var scene_res = load("res://app/scenes/schedules_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "volunteers":
		var scene_res = load("res://app/scenes/volunteers_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "reports":
		var scene_res = load("res://app/scenes/reports_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "settings":
		var scene_res = load("res://app/scenes/settings_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "pathways":
		var scene_res = load("res://app/scenes/pathways_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "attendance":
		var scene_res = load("res://app/scenes/attendance_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
	elif view_name == "kiosk":
		var scene_res = load("res://app/scenes/kiosk_view.tscn")
		if scene_res:
			current_view_node = scene_res.instantiate()
			if "db" in current_view_node:
				current_view_node.db = db
			if current_view_node.has_method("set_app_shell"):
				current_view_node.set_app_shell(self)
	elif view_name == "card_print_queue":
		var dialog_script = load("res://app/scenes/card_print_queue_dialog.gd")
		if dialog_script:
			current_view_node = dialog_script.new(self, db)
			if current_view_node.has_method("show_dialog"):
				current_view_node.show_dialog()
	else:
		return false

	if current_view_node:
		if current_view_node is Control:
			current_view_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			current_view_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
			current_view_node.anchor_left = 0.0
			current_view_node.anchor_top = 0.0
			current_view_node.anchor_right = 1.0
			current_view_node.anchor_bottom = 1.0
			current_view_node.offset_left = 0
			current_view_node.offset_top = 0
			current_view_node.offset_right = 0
			current_view_node.offset_bottom = 0
		if view_name == "kiosk":
			if content_area: content_area.add_child(current_view_node)
		elif view_name == "card_print_queue":
			pass
		else:
			if content_container: content_container.add_child(current_view_node)

		if current_view_node.has_method("receive_navigation_context"):
			current_view_node.call("receive_navigation_context", params.duplicate(true))
		return true

	return false


func _update_nav_button_styles() -> void:
	var buttons = {
		"home": btn_nav_home,
		"people": btn_nav_people,
		"communications": btn_nav_communications,
		"attendance": btn_nav_attendance,
		"schedules": btn_nav_schedules,
		"volunteers": btn_nav_volunteers,
		"pathways": btn_nav_pathways,
		"administration": btn_nav_administration,
		"reports": btn_nav_reports,
		"settings": btn_nav_settings
	}

	var theme_accent = _get_active_theme_color()

	for k in buttons.keys():
		var btn = buttons[k] as Button
		if not btn: continue
		var is_active = (k == current_view_name)
		if is_active:
			var act_style = StyleBoxFlat.new()
			act_style.bg_color = theme_accent
			act_style.corner_radius_top_left = 6
			act_style.corner_radius_bottom_left = 6
			act_style.corner_radius_top_right = 6
			act_style.corner_radius_bottom_right = 6
			act_style.content_margin_left = 18
			btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			btn.add_theme_stylebox_override("normal", act_style)
			btn.add_theme_stylebox_override("hover", act_style)
			btn.add_theme_stylebox_override("pressed", act_style)
		else:
			var inact_style = StyleBoxFlat.new()
			inact_style.bg_color = Color(1.0, 1.0, 1.0, 0.0) # Transparent background when idle
			inact_style.corner_radius_top_left = 6
			inact_style.corner_radius_bottom_left = 6
			inact_style.corner_radius_top_right = 6
			inact_style.corner_radius_bottom_right = 6
			inact_style.content_margin_left = 18
			btn.add_theme_stylebox_override("normal", inact_style)

			# Hover State: Sleek subtle warm highlight so hovering over all options highlights cleanly without disappearing!
			var hov_style = inact_style.duplicate() as StyleBoxFlat
			hov_style.bg_color = Color(1.0, 1.0, 1.0, 0.12)
			btn.add_theme_stylebox_override("hover", hov_style)
			btn.add_theme_stylebox_override("pressed", hov_style)

			btn.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

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

func reload_theme_styles() -> void:
	_apply_pd008_theme_styles()
	_update_nav_button_styles()
