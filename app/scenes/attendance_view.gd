extends "res://app/scenes/standard_page_container.gd"

## Check In Terminal & Attendance Operations View
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")
const BirthdayServiceScript = preload("res://src/domain/birthday/birthday_service.gd")
const PublicQrSignDialogScript = preload("res://app/scenes/public_qr_sign_dialog.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			_init_database()
			_populate_dropdowns()
			_refresh_dashboard()

var att_service: RefCounted
var bday_service: RefCounted
var active_bday_log_id: int = 0
var person_list: Array = []
var filtered_person_list: Array = []
var session_list: Array = []
var current_mode: String = "Daily Check In"
var selected_date_unix: int = 0
var toast_timer: SceneTreeTimer = null

@onready var shift_lead_dropdown: OptionButton = $MarginContainer/MainVBox/TopBarHBox/ShiftLeadHBox/ShiftLeadDropdown
@onready var btn_sign_in_status: Button = $MarginContainer/MainVBox/TopBarHBox/ShiftLeadHBox/BtnSignInStatus

@onready var hero_terminal_card: PanelContainer = $MarginContainer/MainVBox/HeroTerminalCard
@onready var btn_mode_daily: Button = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/PillTabsHBox/BtnModeDaily
@onready var btn_mode_session: Button = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/PillTabsHBox/BtnModeSession
@onready var session_select_vbox: VBoxContainer = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/SessionSelectVBox
@onready var session_dropdown: OptionButton = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/SessionSelectVBox/SessionDropdown

@onready var directory_count_label: Label = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/SearchHeaderHBox/DirectoryCountLabel
@onready var search_line_edit: LineEdit = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/SearchLineEdit
@onready var suggestion_list: ItemList = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/SuggestionList
@onready var toast_panel: PanelContainer = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/ToastPanel
@onready var toast_label: Label = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/ToastPanel/ToastMargin/ToastLabel

@onready var person_dropdown: OptionButton = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/ActionHBox/PersonDropdown
@onready var btn_quick_check_in: Button = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/ActionHBox/BtnQuickCheckIn

@onready var daily_overview_card: PanelContainer = $MarginContainer/MainVBox/DailyOverviewCard
@onready var date_label: Label = $MarginContainer/MainVBox/DailyOverviewCard/OverviewMargin/OverviewVBox/DateNavHBox/DateInfoVBox/DateLabel
@onready var viewing_subtitle: Label = $MarginContainer/MainVBox/DailyOverviewCard/OverviewMargin/OverviewVBox/DateNavHBox/DateInfoVBox/ViewingSubtitle
@onready var btn_prev_day: Button = $MarginContainer/MainVBox/DailyOverviewCard/OverviewMargin/OverviewVBox/DateNavHBox/NavBtnsHBox/BtnPrevDay
@onready var btn_next_day: Button = $MarginContainer/MainVBox/DailyOverviewCard/OverviewMargin/OverviewVBox/DateNavHBox/NavBtnsHBox/BtnNextDay
@onready var btn_date_pick: Button = $MarginContainer/MainVBox/DailyOverviewCard/OverviewMargin/OverviewVBox/DateNavHBox/NavBtnsHBox/BtnDatePick
@onready var metrics_grid: GridContainer = $MarginContainer/MainVBox/DailyOverviewCard/OverviewMargin/OverviewVBox/MetricsGrid

@onready var log_card: PanelContainer = $MarginContainer/MainVBox/LogCard

@onready var birthday_modal: ColorRect = $BirthdayModal
@onready var bday_body_label: Label = $BirthdayModal/ModalCenter/ModalCard/ModalMargin/ModalVBox/BdayBodyLabel
@onready var bday_sms_status_label: Label = $BirthdayModal/ModalCenter/ModalCard/ModalMargin/ModalVBox/BdaySmsStatusLabel
@onready var btn_acknowledge_bday: Button = $BirthdayModal/ModalCenter/ModalCard/ModalMargin/ModalVBox/BtnAcknowledgeBday

@onready var search_title_label: Label = $MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox/SearchHeaderHBox/SearchTitleLabel
@onready var overview_title_label: Label = $MarginContainer/MainVBox/DailyOverviewCard/OverviewMargin/OverviewVBox/DateNavHBox/DateInfoVBox/OverviewTitleLabel

func _create_texture_from_base64(base64_str: String) -> ImageTexture:
	var b64_data = base64_str.strip_edges()
	if b64_data == "" or b64_data.to_lower() == "null" or b64_data.to_lower() == "<null>":
		return null
	if "," in b64_data:
		b64_data = b64_data.split(",")[1]
	var buffer = Marshalls.base64_to_raw(b64_data)
	if buffer.size() == 0:
		return null
	var img = Image.new()
	var err = img.load_jpg_from_buffer(buffer)
	if err != OK:
		err = img.load_png_from_buffer(buffer)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

func _ready() -> void:
	selected_date_unix = int(Time.get_unix_time_from_system())
	_init_database()
	_style_components()
	_populate_dropdowns()
	_connect_signals()
	_update_mode_ui()
	_refresh_dashboard()

	var top_bar = get_node_or_null("MarginContainer/MainVBox/TopBarHBox")
	if top_bar:
		var btn_pub_qr = Button.new()
		btn_pub_qr.text = "🏛️ PUBLIC CHECK-IN QR SIGN"
		btn_pub_qr.custom_minimum_size = Vector2(210, 36)
		btn_pub_qr.pressed.connect(func():
			var dlg = PublicQrSignDialogScript.new(self)
			dlg.show_dialog()
		)
		top_bar.add_child(btn_pub_qr)

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig = MigrationsRunnerScript.new(db)
		mig.run_migrations()
	if not att_service:
		att_service = AttendanceServiceScript.new(db)
	if not bday_service:
		bday_service = BirthdayServiceScript.new(db)

	db.execute("ALTER TABLE attendance_log ADD COLUMN session_id INTEGER DEFAULT NULL;")
	db.execute("ALTER TABLE attendance_log ADD COLUMN mode TEXT DEFAULT 'Daily Check In';")
	db.execute("ALTER TABLE attendance_log ADD COLUMN shift_lead TEXT DEFAULT 'John Boyte';")

func _style_components() -> void:
	var idx = 0
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "0"))

	# Hero Terminal Card styling - premium dark slate container matching Kiosk and Admin view cards
	var hero_st = StyleBoxFlat.new()
	hero_st.bg_color = Color(0.12, 0.16, 0.24, 1.0)
	hero_st.border_width_left = 2; hero_st.border_width_top = 2; hero_st.border_width_right = 2; hero_st.border_width_bottom = 2
	if idx == 0:
		hero_st.border_color = Color(0.384, 0.467, 0.576, 1.0) # AU Blue Border
	else:
		hero_st.border_color = Color(0.24, 0.35, 0.55, 1.0) # Slate Border
	hero_st.corner_radius_top_left = 12; hero_st.corner_radius_top_right = 12; hero_st.corner_radius_bottom_left = 12; hero_st.corner_radius_bottom_right = 12
	hero_terminal_card.add_theme_stylebox_override("panel", hero_st)

	# Main cards styling - high contrast dark slate container for dark mode readability
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(0.14, 0.17, 0.23, 1.0)
	card_st.border_width_left = 2; card_st.border_width_top = 2; card_st.border_width_right = 2; card_st.border_width_bottom = 2
	card_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 20; card_st.content_margin_top = 18; card_st.content_margin_right = 20; card_st.content_margin_bottom = 18
	daily_overview_card.add_theme_stylebox_override("panel", card_st)
	log_card.add_theme_stylebox_override("panel", card_st)

	# Fix date label, headers, and Viewing subtitle contrast & size scaling
	date_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	date_label.add_theme_font_size_override("font_size", 20)
	viewing_subtitle.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
	viewing_subtitle.add_theme_font_size_override("font_size", 13)
	search_title_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
	directory_count_label.add_theme_color_override("font_color", Color(0.50, 0.58, 0.68, 1.0))
	overview_title_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
	overview_title_label.add_theme_font_size_override("font_size", 12)

	# Toast Panel styling
	var toast_st = StyleBoxFlat.new()
	toast_st.bg_color = Color(0.10, 0.45, 0.30, 1.0) # Emerald notification
	toast_st.border_width_left = 1; toast_st.border_width_top = 1; toast_st.border_width_right = 1; toast_st.border_width_bottom = 1
	toast_st.border_color = Color(0.40, 0.95, 0.65, 1.0)
	toast_st.corner_radius_top_left = 8; toast_st.corner_radius_top_right = 8; toast_st.corner_radius_bottom_left = 8; toast_st.corner_radius_bottom_right = 8
	toast_panel.add_theme_stylebox_override("panel", toast_st)

	# Terracotta / Crimson Check-In Button
	_style_button_high_contrast(btn_quick_check_in, _get_active_theme_color(), _get_active_secondary_color(), 18)

	# Nav Buttons - Brand Color Palette for AU Theme
	if idx == 0:
		var au_blue = Color(0.384, 0.467, 0.576, 1.0)
		var au_gold = Color(0.737, 0.635, 0.439, 1.0)
		var au_red = Color(0.596, 0.192, 0.255, 1.0)
		_style_button_high_contrast(btn_prev_day, au_blue, au_gold, 16)
		_style_button_high_contrast(btn_next_day, au_blue, au_gold, 16)
		_style_button_high_contrast(btn_date_pick, au_blue, au_gold, 20)
		_style_button_high_contrast(btn_sign_in_status, au_red, au_gold, 16)
	else:
		_style_button_high_contrast(btn_prev_day, Color(0.20, 0.26, 0.36, 1.0), Color(0.40, 0.55, 0.75, 1.0), 16)
		_style_button_high_contrast(btn_next_day, Color(0.20, 0.26, 0.36, 1.0), Color(0.40, 0.55, 0.75, 1.0), 16)
		_style_button_high_contrast(btn_date_pick, Color(0.20, 0.26, 0.36, 1.0), Color(0.40, 0.60, 0.85, 1.0), 20)
		_style_button_high_contrast(btn_sign_in_status, Color(0.20, 0.26, 0.36, 1.0), Color(0.40, 0.55, 0.75, 1.0), 16)

	# Dropdowns
	_style_option_button(shift_lead_dropdown, 16)
	_style_option_button(session_dropdown, 16)
	_style_option_button(person_dropdown, 17)

	# High-contrast Search Input box
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.06, 0.08, 0.12, 1.0)
	edit_st.border_width_left = 2; edit_st.border_width_top = 2; edit_st.border_width_right = 2; edit_st.border_width_bottom = 2
	edit_st.border_color = Color(0.40, 0.90, 1.0, 1.0)
	edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
	edit_st.content_margin_left = 14; edit_st.content_margin_top = 10; edit_st.content_margin_right = 14; edit_st.content_margin_bottom = 10
	search_line_edit.add_theme_stylebox_override("normal", edit_st)
	search_line_edit.add_theme_stylebox_override("focus", edit_st)
	search_line_edit.add_theme_font_size_override("font_size", 18)
	search_line_edit.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	search_line_edit.add_theme_color_override("font_placeholder_color", Color(0.75, 0.85, 1.0, 1.0))

	# High-contrast Suggestion List
	var sug_st = StyleBoxFlat.new()
	sug_st.bg_color = Color(0.08, 0.12, 0.20, 1.0)
	sug_st.border_width_left = 2; sug_st.border_width_top = 2; sug_st.border_width_right = 2; sug_st.border_width_bottom = 2
	sug_st.border_color = Color(0.40, 0.70, 1.0, 1.0)
	sug_st.corner_radius_top_left = 6; sug_st.corner_radius_top_right = 6; sug_st.corner_radius_bottom_left = 6; sug_st.corner_radius_bottom_right = 6
	sug_st.content_margin_left = 12; sug_st.content_margin_top = 8; sug_st.content_margin_right = 12; sug_st.content_margin_bottom = 8
	suggestion_list.add_theme_stylebox_override("panel", sug_st)
	suggestion_list.add_theme_font_size_override("font_size", 17)
	suggestion_list.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

func _style_button_high_contrast(btn: Button, bg_col: Color, border_col: Color, font_size: int = 16) -> void:
	var st = StyleBoxFlat.new()
	st.bg_color = bg_col
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
	st.border_color = border_col
	st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
	st.content_margin_left = 12; st.content_margin_top = 8; st.content_margin_right = 12; st.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", st)
	btn.add_theme_stylebox_override("pressed", st)
	btn.add_theme_stylebox_override("focus", st)
	btn.add_theme_font_size_override("font_size", font_size)

	# Dynamic luminance font contrast calculation for high contrast AAA readability
	var lum = 0.2126 * bg_col.r + 0.7152 * bg_col.g + 0.0722 * bg_col.b
	var fg = Color(1.0, 1.0, 1.0, 1.0) if lum < 0.55 else Color(0.08, 0.12, 0.18, 1.0)

	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_color_override("font_focus_color", fg)

func _style_option_button(opt: OptionButton, font_size: int = 16) -> void:
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
	st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
	st.content_margin_left = 12; st.content_margin_top = 8; st.content_margin_right = 12; st.content_margin_bottom = 8
	opt.add_theme_stylebox_override("normal", st)
	opt.add_theme_stylebox_override("hover", st)
	opt.add_theme_stylebox_override("pressed", st)
	opt.add_theme_stylebox_override("focus", st)
	opt.add_theme_font_size_override("font_size", font_size)
	opt.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	opt.add_theme_color_override("font_hover_color", Color(0.08, 0.12, 0.18, 1.0))
	opt.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	opt.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))

func _populate_dropdowns() -> void:
	shift_lead_dropdown.clear()
	shift_lead_dropdown.add_item("John Boyte", 0)
	shift_lead_dropdown.add_item("Sarah Jenkins", 1)
	shift_lead_dropdown.add_item("Michael Chen", 2)
	shift_lead_dropdown.select(0)

	person_dropdown.clear()
	person_list.clear()

	var p_res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name FROM people ORDER BY last_name ASC, first_name ASC;")
	if p_res["success"] and p_res["data"].size() > 0:
		person_list = p_res["data"]
		filtered_person_list = person_list.duplicate()
		_update_person_dropdown_list(person_list)
		directory_count_label.text = "Directory members loaded: " + str(person_list.size())
	else:
		person_dropdown.add_item("No constituents found", 0)
		directory_count_label.text = "Directory members loaded: 0"

	session_dropdown.clear()
	session_list.clear()
	var s_res = db.execute("SELECT id, title, session_type, date_text, start_time, end_time, room_location FROM sessions WHERE is_active = 1 ORDER BY date_text DESC, start_time ASC;")
	if s_res["success"] and s_res["data"].size() > 0:
		session_list = s_res["data"]
		for i in range(session_list.size()):
			var s = session_list[i]
			var t = str(s.get("title", "Session"))
			var dt = str(s.get("date_text", ""))
			var st = str(s.get("start_time", ""))
			var rm = str(s.get("room_location", ""))
			var label = t + " (" + dt + " " + st + " • " + rm + ")"
			session_dropdown.add_item(label, i)
	else:
		session_dropdown.add_item("— Choose a session —", 0)

func _update_person_dropdown_list(list: Array) -> void:
	person_dropdown.clear()
	for i in range(list.size()):
		var p = list[i]
		var fn = str(p.get("first_name", ""))
		var ln = str(p.get("last_name", ""))
		var hid = str(p.get("human_id", ""))
		var name = (fn + " " + ln).strip_edges() + " (" + hid + ")"
		person_dropdown.add_item(name, i)

func _connect_signals() -> void:
	if btn_mode_daily: btn_mode_daily.pressed.connect(func(): _switch_mode("Daily Check In"))
	if btn_mode_session: btn_mode_session.pressed.connect(func(): _switch_mode("Session Attendance"))
	if btn_quick_check_in: btn_quick_check_in.pressed.connect(_on_record_check_in)
	if search_line_edit:
		search_line_edit.text_changed.connect(_on_search_text_changed)
		search_line_edit.text_submitted.connect(_on_search_text_submitted)
	if suggestion_list:
		suggestion_list.item_selected.connect(_on_suggestion_item_selected)
	if btn_prev_day: btn_prev_day.pressed.connect(_on_prev_day_pressed)
	if btn_next_day: btn_next_day.pressed.connect(_on_next_day_pressed)
	if btn_acknowledge_bday: btn_acknowledge_bday.pressed.connect(_on_acknowledge_bday_pressed)

func _on_acknowledge_bday_pressed() -> void:
	if bday_service and active_bday_log_id > 0:
		bday_service.acknowledge_birthday_alert(active_bday_log_id)
	birthday_modal.visible = false

func _dismiss_toast() -> void:
	if toast_panel: toast_panel.visible = false

func _switch_mode(new_mode: String) -> void:
	current_mode = new_mode
	_dismiss_toast()
	_update_mode_ui()

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

func _update_mode_ui() -> void:
	var primary_col = _get_active_theme_color()
	var sec_col = _get_active_secondary_color()

	var active_st = StyleBoxFlat.new()
	active_st.bg_color = primary_col
	active_st.border_width_left = 1; active_st.border_width_top = 1; active_st.border_width_right = 1; active_st.border_width_bottom = 1
	active_st.border_color = sec_col
	active_st.corner_radius_top_left = 6; active_st.corner_radius_top_right = 6; active_st.corner_radius_bottom_left = 6; active_st.corner_radius_bottom_right = 6

	var inactive_st = StyleBoxFlat.new()
	inactive_st.bg_color = Color(0.94, 0.96, 0.98, 1.0)
	inactive_st.corner_radius_top_left = 6; inactive_st.corner_radius_top_right = 6; inactive_st.corner_radius_bottom_left = 6; inactive_st.corner_radius_bottom_right = 6

	var inactive_hover_st = StyleBoxFlat.new()
	inactive_hover_st.bg_color = Color(0.97, 0.98, 1.0, 1.0)
	inactive_hover_st.border_width_left = 1; inactive_hover_st.border_width_top = 1; inactive_hover_st.border_width_right = 1; inactive_hover_st.border_width_bottom = 1
	inactive_hover_st.border_color = sec_col
	inactive_hover_st.corner_radius_top_left = 6; inactive_hover_st.corner_radius_top_right = 6; inactive_hover_st.corner_radius_bottom_left = 6; inactive_hover_st.corner_radius_bottom_right = 6

	var active_hover_st = StyleBoxFlat.new()
	active_hover_st.bg_color = primary_col.lightened(0.08)
	active_hover_st.corner_radius_top_left = 6; active_hover_st.corner_radius_top_right = 6; active_hover_st.corner_radius_bottom_left = 6; active_hover_st.corner_radius_bottom_right = 6

	if current_mode == "Daily Check In":
		btn_mode_daily.add_theme_stylebox_override("normal", active_st)
		btn_mode_daily.add_theme_stylebox_override("hover", active_hover_st)
		btn_mode_daily.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn_mode_daily.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn_mode_daily.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
		btn_mode_daily.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

		btn_mode_session.add_theme_stylebox_override("normal", inactive_st)
		btn_mode_session.add_theme_stylebox_override("hover", inactive_hover_st)
		btn_mode_session.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
		btn_mode_session.add_theme_color_override("font_hover_color", primary_col)
		btn_mode_session.add_theme_color_override("font_pressed_color", primary_col)
		btn_mode_session.add_theme_color_override("font_focus_color", primary_col)

		session_select_vbox.visible = false
		btn_quick_check_in.text = "✔ CHECK IN"
	else:
		btn_mode_session.add_theme_stylebox_override("normal", active_st)
		btn_mode_session.add_theme_stylebox_override("hover", active_hover_st)
		btn_mode_session.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn_mode_session.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		btn_mode_session.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
		btn_mode_session.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

		btn_mode_daily.add_theme_stylebox_override("normal", inactive_st)
		btn_mode_daily.add_theme_stylebox_override("hover", inactive_hover_st)
		btn_mode_daily.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
		btn_mode_daily.add_theme_color_override("font_hover_color", primary_col)
		btn_mode_daily.add_theme_color_override("font_pressed_color", primary_col)
		btn_mode_daily.add_theme_color_override("font_focus_color", primary_col)

		session_select_vbox.visible = true
		btn_quick_check_in.text = "✔ CHECK IN TO SESSION"

func _on_search_text_changed(query: String) -> void:
	_dismiss_toast()
	var q = query.strip_edges().to_lower()
	if q == "":
		filtered_person_list = person_list.duplicate()
		_update_person_dropdown_list(person_list)
		suggestion_list.visible = false
		return

	filtered_person_list = []
	suggestion_list.clear()

	for p in person_list:
		var fn = str(p.get("first_name", "")).to_lower()
		var ln = str(p.get("last_name", "")).to_lower()
		var hid = str(p.get("human_id", "")).to_lower()
		var full = (fn + " " + ln).strip_edges()
		if q in fn or q in ln or q in full or q in hid:
			filtered_person_list.append(p)
			var disp_name = str(p.get("first_name", "")) + " " + str(p.get("last_name", "")) + " (" + str(p.get("human_id", "")) + ")"
			suggestion_list.add_item("👤 " + disp_name)

	_update_person_dropdown_list(filtered_person_list)
	suggestion_list.visible = (filtered_person_list.size() > 0)

func _on_suggestion_item_selected(index: int) -> void:
	_dismiss_toast()
	if index >= 0 and index < filtered_person_list.size():
		person_dropdown.select(index)
		search_line_edit.text = str(filtered_person_list[index].get("first_name", "")) + " " + str(filtered_person_list[index].get("last_name", ""))
		suggestion_list.visible = false

func _on_search_text_submitted(new_text: String) -> void:
	_dismiss_toast()
	var val = new_text.strip_edges()
	if val == "": return

	var token_candidate = val
	if "credential=" in val:
		var parts = val.split("credential=")
		if parts.size() > 1:
			token_candidate = parts[1].split("&")[0].strip_edges()

	var token_hash = token_candidate.sha256_text()

	# 1. Check if input matches an active QR code credential
	var qr_res = db.execute("SELECT person_id FROM participant_qr_credentials WHERE (token_hash = ? OR token_hash = ?) AND status = 'active' LIMIT 1;", [token_hash, token_candidate])
	if qr_res["success"] and qr_res["data"].size() > 0:
		var pid = int(qr_res["data"][0]["person_id"])
		_execute_check_in_for_person_id(pid, "Self Service QR Scanner")
		search_line_edit.clear()
		suggestion_list.visible = false
		return

	# Check legacy qr_code_value field directly
	var people_qr_res = db.execute("SELECT id FROM people WHERE qr_code_value = ? OR qr_code_value = ? LIMIT 1;", [val, token_candidate])
	if people_qr_res["success"] and people_qr_res["data"].size() > 0:
		var pid = int(people_qr_res["data"][0]["id"])
		_execute_check_in_for_person_id(pid, "Self Service QR Scanner")
		search_line_edit.clear()
		suggestion_list.visible = false
		return


	# 2. Check if input is "ID:PIN" shortcut (e.g. "PRT-1001:1234")
	if val.contains(":"):
		var parts = val.split(":")
		if parts.size() == 2:
			var hid = parts[0].strip_edges()
			var pin = parts[1].strip_edges()
			var p_res = db.execute("SELECT id FROM people WHERE human_id = ? LIMIT 1;", [hid])
			if p_res["success"] and p_res["data"].size() > 0:
				var pid = int(p_res["data"][0]["id"])
				var pin_check = db.execute("SELECT id FROM participant_pin_credentials WHERE person_id = ? AND pin_hash = ? AND status = 'active' LIMIT 1;", [pid, pin])
				if pin_check["success"] and pin_check["data"].size() > 0:
					_execute_check_in_for_person_id(pid, "Self Service PIN")
					search_line_edit.clear()
					suggestion_list.visible = false
					return
				else:
					_show_toast_message("❌ Invalid PIN entered for student ID: " + hid)
					search_line_edit.clear()
					suggestion_list.visible = false
					return

	# 3. Check if input matches a Student/Human ID (trigger PIN popup flow)
	var id_res = db.execute("SELECT id, first_name, last_name, person_uuid FROM people WHERE human_id = ? LIMIT 1;", [val])
	if id_res["success"] and id_res["data"].size() > 0:
		var person = id_res["data"][0]
		_open_checkin_pin_verification_dialog(person)
		search_line_edit.clear()
		suggestion_list.visible = false
		return

	# 4. Fallback: Normal Roster Search auto-select check-in
	if filtered_person_list.size() > 0:
		person_dropdown.select(0)
		_on_record_check_in()
		search_line_edit.clear()
		suggestion_list.visible = false

func _execute_check_in_for_person_id(pid: int, method: String) -> void:
	var res_p = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [pid])
	if not res_p["success"] or res_p["data"].size() == 0:
		_show_toast_message("❌ Error retrieving student information.")
		return
	
	var person = res_p["data"][0]
	var sess_id = null
	if current_mode == "Session Attendance" and session_list.size() > 0:
		var s_idx = session_dropdown.selected
		if s_idx >= 0 and s_idx < session_list.size():
			sess_id = int(session_list[s_idx].get("id", 0))

	var lead = shift_lead_dropdown.get_item_text(shift_lead_dropdown.selected) if shift_lead_dropdown.selected >= 0 else "Sarah Jenkins"

	# Record main check-in
	var res = att_service.record_check_in_atomic(person, method, "dev_macbook_primary_node", sess_id, current_mode, lead)
	if not res["success"]:
		_show_toast_message("❌ Check-in failed.")
		return

	print("Check-In recorded successfully: ", res["checkin_uuid"])
	_refresh_dashboard()

	var fn = str(person.get("first_name", "")) + " " + str(person.get("last_name", ""))
	var mode_name = "Session Attendance" if current_mode == "Session Attendance" else "Daily Attendance"
	_show_toast_message("✨ Check-in complete: " + fn.strip_edges() + " is checked in for " + mode_name)

	# Handle auto daily checkin when checking into session
	if current_mode == "Session Attendance":
		var today_str = Time.get_date_string_from_system()
		var check_daily_res = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id = ? AND check_in_date = ? AND (mode = 'Daily Check In' OR mode = 'Study Center Daily');", [pid, today_str])
		var already_daily = (check_daily_res["success"] and check_daily_res["data"].size() > 0 and int(check_daily_res["data"][0]["cnt"]) > 0)
		if not already_daily:
			att_service.record_check_in_atomic(person, method, "dev_macbook_primary_node", null, "Daily Check In", lead)
			_show_toast_message("✨ Checked in for Session & Daily Attendance: " + fn.strip_edges())

func _show_toast_message(text: String) -> void:
	if not toast_panel or not toast_label: return
	_dismiss_toast()
	toast_label.text = text
	toast_panel.visible = true
	toast_timer = get_tree().create_timer(4.0)
	toast_timer.timeout.connect(func():
		if is_instance_valid(toast_panel):
			toast_panel.visible = false
	)

func _open_checkin_pin_verification_dialog(person: Dictionary) -> void:
	var name_str = str(person.get("first_name", "")) + " " + str(person.get("last_name", ""))
	var pid = int(person.get("id", 0))
	_show_checkin_pin_modal(
		"Enter PIN for " + name_str.strip_edges(),
		"Type 4-digit PIN to confirm...",
		"Verify PIN",
		func(pin):
			var pin_check = db.execute("SELECT id FROM participant_pin_credentials WHERE person_id = ? AND pin_hash = ? AND status = 'active' LIMIT 1;", [pid, pin])
			if pin_check["success"] and pin_check["data"].size() > 0:
				_execute_check_in_for_person_id(pid, "Self Service PIN")
			else:
				_show_toast_message("❌ Invalid PIN code entered.")
	)

func _show_checkin_pin_modal(title: String, placeholder: String, button_text: String, callback: Callable) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(overlay)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 200)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(0.14, 0.17, 0.23, 1.0)
	card_st.border_width_left = 2; card_st.border_width_top = 2; card_st.border_width_right = 2; card_st.border_width_bottom = 2
	card_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 24; card_st.content_margin_right = 24; card_st.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", card_st)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	
	var lbl_title = Label.new()
	lbl_title.text = title
	lbl_title.add_theme_font_size_override("font_size", 18)
	lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	vbox.add_child(lbl_title)
	
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = true
	edit.custom_minimum_size = Vector2(0, 44)
	edit.add_theme_font_size_override("font_size", 16)
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.06, 0.08, 0.12, 1.0)
	edit_st.border_width_left = 1; edit_st.border_width_top = 1; edit_st.border_width_right = 1; edit_st.border_width_bottom = 1
	edit_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
	edit_st.content_margin_left = 10; edit_st.content_margin_right = 10
	edit.add_theme_stylebox_override("normal", edit_st)
	vbox.add_child(edit)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(100, 38)
	btn_cancel.add_theme_font_size_override("font_size", 15)
	btn_cancel.pressed.connect(func():
		overlay.queue_free()
	)
	
	var btn_submit = Button.new()
	btn_submit.text = button_text
	btn_submit.custom_minimum_size = Vector2(140, 38)
	btn_submit.add_theme_font_size_override("font_size", 15)
	
	var active_color = _get_active_theme_color()
	var submit_st = StyleBoxFlat.new()
	submit_st.bg_color = active_color
	submit_st.corner_radius_top_left = 6; submit_st.corner_radius_top_right = 6; submit_st.corner_radius_bottom_left = 6; submit_st.corner_radius_bottom_right = 6
	btn_submit.add_theme_stylebox_override("normal", submit_st)
	btn_submit.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	
	btn_submit.pressed.connect(func():
		var val = edit.text.strip_edges()
		if val != "":
			callback.call(val)
			overlay.queue_free()
	)
	
	edit.text_submitted.connect(func(new_txt):
		var val = new_txt.strip_edges()
		if val != "":
			callback.call(val)
			overlay.queue_free()
	)
	
	hbox.add_child(btn_cancel)
	hbox.add_child(btn_submit)
	vbox.add_child(hbox)
	
	card.add_child(vbox)
	
	var center = CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.add_child(card)
	overlay.add_child(center)
	
	edit.grab_focus()

func _on_record_check_in() -> void:
	_dismiss_toast()
	if filtered_person_list.size() == 0: return

	var sel_p_idx = person_dropdown.selected
	if sel_p_idx < 0 or sel_p_idx >= filtered_person_list.size(): return
	var person = filtered_person_list[sel_p_idx]
	var method = "Staff Manual"

	var sess_id = null
	if current_mode == "Session Attendance" and session_list.size() > 0:
		var s_idx = session_dropdown.selected
		if s_idx >= 0 and s_idx < session_list.size():
			sess_id = int(session_list[s_idx].get("id", 0))

	var lead = shift_lead_dropdown.get_item_text(shift_lead_dropdown.selected)

	# 1. Record the primary check-in
	var res = att_service.record_check_in_atomic(person, method, "dev_macbook_primary_node", sess_id, current_mode, lead)
	if not res["success"]: return

	print("Check-In recorded successfully: ", res["checkin_uuid"])

	# Requirement 3: If checking into a session, check if automatically checked in for daily attendance today
	if current_mode == "Session Attendance":
		var p_id = int(person.get("id", 0))
		var today_str = Time.get_date_string_from_system()

		var check_daily_res = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id = ? AND check_in_date = ? AND (mode = 'Daily Check In' OR mode = 'Study Center Daily');", [p_id, today_str])
		var already_daily = (check_daily_res["success"] and check_daily_res["data"].size() > 0 and int(check_daily_res["data"][0]["cnt"]) > 0)

		if not already_daily:
			# Automatically check them in for Daily Attendance as well
			att_service.record_check_in_atomic(person, method, "dev_macbook_primary_node", null, "Daily Check In", lead)

			# Show Friendly Toast Banner
			var fn = str(person.get("first_name", "")) + " " + str(person.get("last_name", ""))
			toast_label.text = "✨ Check-In Complete! " + fn.strip_edges() + " has also been automatically checked in for Today's Daily Attendance."
			toast_panel.visible = true

			# Auto-dismiss after 4 seconds
			get_tree().create_timer(4.0).timeout.connect(func():
				if is_instance_valid(toast_panel): toast_panel.visible = false
			)

	# Evaluate Birthday Alert & Team SMS Notification
	if bday_service:
		var bday_res = bday_service.evaluate_checkin_birthday(person)
		if bday_res.get("trigger_alert", false):
			active_bday_log_id = int(bday_res.get("log_id", 0))
			var notif_type = str(bday_res.get("notification_type", ""))
			var fn = (str(person.get("first_name", "")) + " " + str(person.get("last_name", ""))).strip_edges()

			if notif_type == "birthday_today":
				bday_body_label.text = "Today is " + fn + "'s birthday!"
			else:
				var month_names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
				var bm_str = month_names[int(bday_res.get("birth_month", 1)) - 1]
				var bd_str = str(bday_res.get("birth_day", 1))
				bday_body_label.text = fn + "'s birthday is " + bm_str + " " + bd_str + ". Today is the last day the center is open before her birthday."

			if bday_res.get("already_logged", false):
				bday_sms_status_label.text = "ℹ️ The team has already been notified."
			else:
				var sms_res = bday_service.dispatch_team_birthday_sms(person, notif_type, active_bday_log_id)
				bday_sms_status_label.text = "📲 Active shift team notified via SMS."

			birthday_modal.visible = true

	# Check for Queued Check-In Messages / Alerts for this constituent
	var person_uuid = str(person.get("person_uuid", ""))
	if db and person_uuid != "":
		var msg_res = db.execute("SELECT id, payload FROM event_outbox WHERE aggregate_id = ? AND event_type = 'CHECKIN_MESSAGE_QUEUED' ORDER BY id ASC LIMIT 1;", [person_uuid])
		if msg_res["success"] and msg_res["data"].size() > 0:
			var msg_row = msg_res["data"][0]
			var msg_id = int(msg_row["id"])
			var msg_body = str(msg_row["payload"])
			_show_checkin_message_modal(person, msg_id, msg_body)

	search_line_edit.clear()
	suggestion_list.visible = false
	_refresh_dashboard()

func _show_checkin_message_modal(person: Dictionary, msg_id: int, msg_body: String) -> void:
	var fn = (str(person.get("first_name", "")) + " " + str(person.get("last_name", ""))).strip_edges()

	var modal = ColorRect.new()
	modal.color = Color(0.06, 0.09, 0.14, 0.85)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.z_index = 100

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.14, 0.18, 0.26, 1.0)
	st.border_width_left = 2; st.border_width_top = 2; st.border_width_right = 2; st.border_width_bottom = 2
	st.border_color = Color(0.88, 0.35, 0.21, 1.0)
	st.corner_radius_top_left = 12; st.corner_radius_top_right = 12; st.corner_radius_bottom_left = 12; st.corner_radius_bottom_right = 12
	st.content_margin_left = 24; st.content_margin_top = 24; st.content_margin_right = 24; st.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", st)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)

	var title_lbl = Label.new()
	title_lbl.text = "💬 Check-In Staff Alert / Message"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40, 1.0))
	vbox.add_child(title_lbl)

	var member_lbl = Label.new()
	member_lbl.text = "Member: " + fn + " (" + str(person.get("human_id", "")) + ")"
	member_lbl.add_theme_font_size_override("font_size", 16)
	member_lbl.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0))
	vbox.add_child(member_lbl)

	var body_box = PanelContainer.new()
	var b_st = StyleBoxFlat.new()
	b_st.bg_color = Color(0.10, 0.13, 0.19, 1.0)
	b_st.corner_radius_top_left = 8; b_st.corner_radius_top_right = 8; b_st.corner_radius_bottom_left = 8; b_st.corner_radius_bottom_right = 8
	b_st.content_margin_left = 16; b_st.content_margin_top = 14; b_st.content_margin_right = 16; b_st.content_margin_bottom = 14
	body_box.add_theme_stylebox_override("panel", b_st)

	var body_lbl = Label.new()
	body_lbl.text = msg_body
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_size_override("font_size", 16)
	body_lbl.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	body_box.add_child(body_lbl)
	vbox.add_child(body_box)

	var btn_ack = Button.new()
	btn_ack.text = "✔ Acknowledge & Clear Alert"
	btn_ack.custom_minimum_size = Vector2(0, 44)
	btn_ack.add_theme_font_size_override("font_size", 16)
	btn_ack.pressed.connect(func():
		if db:
			db.execute("UPDATE event_outbox SET event_type = 'CHECKIN_MESSAGE_CONSUMED' WHERE id = ?;", [msg_id])
		modal.queue_free()
	)
	vbox.add_child(btn_ack)

	panel.add_child(vbox)
	center.add_child(panel)
	modal.add_child(center)
	add_child(modal)

func _on_prev_day_pressed() -> void:
	_dismiss_toast()
	selected_date_unix -= 86400
	_refresh_dashboard()

func _on_next_day_pressed() -> void:
	_dismiss_toast()
	selected_date_unix += 86400
	_refresh_dashboard()

func _refresh_dashboard() -> void:
	var date_dict = Time.get_datetime_dict_from_unix_time(selected_date_unix)
	var date_str = "%04d-%02d-%02d" % [date_dict["year"], date_dict["month"], date_dict["day"]]

	var day_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	var month_names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	var wday_name = day_names[int(date_dict["weekday"])]
	var m_name = month_names[int(date_dict["month"]) - 1]

	date_label.text = "%s, %s %d, %d" % [wday_name, m_name, date_dict["day"], date_dict["year"]]
	btn_date_pick.text = "📅 %02d/%02d/%04d" % [date_dict["month"], date_dict["day"], date_dict["year"]]

	var today_str = Time.get_date_string_from_system()
	if date_str == today_str:
		viewing_subtitle.text = "Viewing today"
	else:
		viewing_subtitle.text = "Viewing " + date_str

	_render_metrics(date_str)
	_render_checkin_log(date_str)

func _render_metrics(date_str: String) -> void:
	for c in metrics_grid.get_children(): c.free()

	var res = db.execute("SELECT a.id, p.primary_role FROM attendance_log a LEFT JOIN people p ON p.id = a.person_id WHERE a.check_in_date = ?;", [date_str])
	var total_present = 0
	var count_vol = 0
	var count_int = 0
	var count_stf = 0
	var count_par = 0

	if res["success"] and res["data"].size() > 0:
		total_present = res["data"].size()
		for item in res["data"]:
			var r = str(item.get("primary_role", "")).to_lower()
			if "vol" in r: count_vol += 1
			elif "int" in r or "fel" in r: count_int += 1
			elif "staff" in r or "lead" in r: count_stf += 1
			else: count_par += 1

	# Check active theme index
	var idx = 0
	if db:
		var res_idx = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res_idx["success"] and res_idx["data"].size() > 0:
			idx = int(res_idx["data"][0].get("setting_value", "0"))

	if idx == 0:
		# AU Brand Colors: AU Blue (#627793), AU Green (#6C7B60), AU Crimson (#983141), AU Gold (#BCA270)
		_add_metric_card("TOTAL PRESENT", total_present, "👥", Color(0.384, 0.467, 0.576, 1.0), Color(0.737, 0.635, 0.439, 1.0), Color(1.0, 1.0, 1.0, 1.0))
		_add_metric_card("VOLUNTEERS", count_vol, "🧑‍🏫", Color(0.424, 0.482, 0.376, 1.0), Color(0.737, 0.635, 0.439, 1.0), Color(1.0, 1.0, 1.0, 1.0))
		_add_metric_card("INTERNS", count_int, "🎓", Color(0.596, 0.192, 0.255, 1.0), Color(0.737, 0.635, 0.439, 1.0), Color(1.0, 1.0, 1.0, 1.0))
		_add_metric_card("STAFF", count_stf, "💼", Color(0.737, 0.635, 0.439, 1.0), Color(0.969, 0.953, 0.929, 1.0), Color(0.08, 0.12, 0.18, 1.0))
		_add_metric_card("PARTICIPANTS", count_par, "👤", Color(0.384, 0.467, 0.576, 1.0), Color(0.737, 0.635, 0.439, 1.0), Color(1.0, 1.0, 1.0, 1.0))
	else:
		_add_metric_card("TOTAL PRESENT", total_present, "👥", Color(0.15, 0.28, 0.60, 1.0), Color(0.40, 0.65, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0))
		_add_metric_card("VOLUNTEERS", count_vol, "🧑‍🏫", Color(0.10, 0.35, 0.20, 1.0), Color(0.35, 0.75, 0.50, 1.0), Color(1.0, 1.0, 1.0, 1.0))
		_add_metric_card("INTERNS", count_int, "🎓", Color(0.25, 0.15, 0.45, 1.0), Color(0.60, 0.45, 0.90, 1.0), Color(1.0, 1.0, 1.0, 1.0))
		_add_metric_card("STAFF", count_stf, "💼", Color(0.85, 0.45, 0.15, 1.0), Color(1.0, 0.70, 0.30, 1.0), Color(1.0, 1.0, 1.0, 1.0))
		_add_metric_card("PARTICIPANTS", count_par, "👤", Color(0.08, 0.30, 0.38, 1.0), Color(0.30, 0.70, 0.85, 1.0), Color(1.0, 1.0, 1.0, 1.0))

func _add_metric_card(title: String, count: int, icon_str: String, bg_col: Color, border_col: Color, text_col: Color) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var st = StyleBoxFlat.new()
	st.bg_color = bg_col
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
	st.border_color = border_col
	st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
	st.content_margin_left = 12; st.content_margin_top = 8; st.content_margin_right = 12; st.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", st)

	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 4)

	var top_hbox = HBoxContainer.new()
	var lbl_t = Label.new(); lbl_t.text = title; lbl_t.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl_t.add_theme_font_size_override("font_size", 11); lbl_t.add_theme_color_override("font_color", text_col)
	top_hbox.add_child(lbl_t)

	var lbl_i = Label.new(); lbl_i.text = icon_str; lbl_i.add_theme_font_size_override("font_size", 13)
	top_hbox.add_child(lbl_i)
	vbox.add_child(top_hbox)

	var lbl_c = Label.new(); lbl_c.text = str(count)
	lbl_c.add_theme_font_size_override("font_size", 24); lbl_c.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	vbox.add_child(lbl_c)

	card.add_child(vbox)
	metrics_grid.add_child(card)

func _render_checkin_log(date_str: String) -> void:
	for child in log_card.get_children(): child.free()

	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 14)

	# Card Header
	var header_hbox = HBoxContainer.new()
	var head_vbox = VBoxContainer.new(); head_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	var title_lbl = Label.new(); title_lbl.text = "Recent Check-ins"; title_lbl.add_theme_font_size_override("font_size", 22); title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	head_vbox.add_child(title_lbl)
	var sub_lbl = Label.new(); sub_lbl.text = "All check-ins for the selected date, newest first."; sub_lbl.add_theme_font_size_override("font_size", 16); sub_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	head_vbox.add_child(sub_lbl)
	header_hbox.add_child(head_vbox)

	var btn_refresh = Button.new(); btn_refresh.text = "🔄 Refresh"; btn_refresh.custom_minimum_size = Vector2(110, 40)
	_style_button_high_contrast(btn_refresh, Color(0.20, 0.26, 0.36, 1.0), Color(0.40, 0.55, 0.75, 1.0), 16)
	btn_refresh.pressed.connect(func(): _refresh_dashboard())
	header_hbox.add_child(btn_refresh)
	vbox.add_child(header_hbox)

	var res = db.execute("SELECT a.id, a.checkin_uuid, a.human_id, a.check_in_date, a.check_in_time, a.method, a.mode, p.first_name, p.last_name, p.primary_role, p.profile_photo FROM attendance_log a LEFT JOIN people p ON p.id = a.person_id WHERE a.check_in_date = ? ORDER BY a.id DESC;", [date_str])

	if res["success"] and res["data"].size() > 0:
		var scroll = ScrollContainer.new(); scroll.custom_minimum_size = Vector2(0, 340); scroll.size_flags_vertical = SIZE_EXPAND_FILL
		var list_vbox = VBoxContainer.new(); list_vbox.size_flags_horizontal = SIZE_EXPAND_FILL; list_vbox.add_theme_constant_override("separation", 10)

		for item in res["data"]:
			var cid = int(item.get("id", 0))
			var first = str(item.get("first_name")) if item.get("first_name") != null else ""
			var last = str(item.get("last_name")) if item.get("last_name") != null else ""
			var name = (first + " " + last).strip_edges()
			if name == "": name = str(item.get("human_id")) if item.get("human_id") != null else "Constituent"

			var time_s = str(item.get("check_in_time")) if item.get("check_in_time") != null else ""
			var mode_s = str(item.get("mode")) if item.get("mode") != null else "Facility"
			var role_s = str(item.get("primary_role")) if item.get("primary_role") != null else "Member"

			var row_card = PanelContainer.new()
			var st = StyleBoxFlat.new()
			st.bg_color = Color(0.18, 0.22, 0.30, 1.0)
			st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
			st.border_color = Color(0.32, 0.42, 0.58, 1.0)
			st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
			st.content_margin_left = 14; st.content_margin_top = 10; st.content_margin_right = 14; st.content_margin_bottom = 10
			row_card.add_theme_stylebox_override("panel", st)

			var r_hbox = HBoxContainer.new(); r_hbox.add_theme_constant_override("separation", 14)

			var photo_tex = _create_texture_from_base64(String(item.get("profile_photo")) if item.get("profile_photo") != null else "")
			if photo_tex:
				var avatar_rect = TextureRect.new()
				avatar_rect.texture = photo_tex
				avatar_rect.custom_minimum_size = Vector2(36, 36)
				avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				r_hbox.add_child(avatar_rect)

			var time_lbl = Label.new(); time_lbl.text = "🕒 " + time_s; time_lbl.custom_minimum_size = Vector2(110, 0)
			time_lbl.add_theme_font_size_override("font_size", 16); time_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0, 1.0))
			r_hbox.add_child(time_lbl)

			var name_lbl = Label.new(); name_lbl.text = name + " (" + str(item.get("human_id")) + ")"; name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			name_lbl.add_theme_font_size_override("font_size", 17); name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			r_hbox.add_child(name_lbl)

			var role_lbl = Label.new(); role_lbl.text = "Role: " + role_s; role_lbl.add_theme_font_size_override("font_size", 15); role_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
			r_hbox.add_child(role_lbl)

			var meth_lbl = Label.new(); meth_lbl.text = "Mode: " + mode_s; meth_lbl.add_theme_font_size_override("font_size", 15); meth_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			r_hbox.add_child(meth_lbl)

			var btn_undo = Button.new(); btn_undo.text = "🗑️ Undo"; btn_undo.custom_minimum_size = Vector2(85, 34)
			_style_button_high_contrast(btn_undo, Color(0.75, 0.20, 0.20, 1.0), Color(0.95, 0.40, 0.40, 1.0), 14)
			btn_undo.pressed.connect(func(): _undo_check_in(cid))
			r_hbox.add_child(btn_undo)

			row_card.add_child(r_hbox)
			list_vbox.add_child(row_card)

		scroll.add_child(list_vbox)
		vbox.add_child(scroll)
	else:
		var empty_panel = PanelContainer.new()
		var empty_st = StyleBoxFlat.new()
		empty_st.bg_color = Color(0.18, 0.22, 0.30, 1.0)
		empty_st.border_width_left = 1; empty_st.border_width_top = 1; empty_st.border_width_right = 1; empty_st.border_width_bottom = 1
		empty_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
		empty_st.corner_radius_top_left = 8; empty_st.corner_radius_top_right = 8; empty_st.corner_radius_bottom_left = 8; empty_st.corner_radius_bottom_right = 8
		empty_st.content_margin_left = 24; empty_st.content_margin_top = 40; empty_st.content_margin_right = 24; empty_st.content_margin_bottom = 40
		empty_panel.add_theme_stylebox_override("panel", empty_st)

		var evbox = VBoxContainer.new(); evbox.add_theme_constant_override("separation", 10); evbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon_lbl = Label.new(); icon_lbl.text = "🕒"; icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 40); icon_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 1.0, 1.0))
		evbox.add_child(icon_lbl)

		var msg_lbl = Label.new(); msg_lbl.text = "No check-ins recorded for this date."; msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg_lbl.add_theme_font_size_override("font_size", 18); msg_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		evbox.add_child(msg_lbl)

		var sub_msg = Label.new(); sub_msg.text = "Try a different date, or check in a member above to populate this list."; sub_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_msg.add_theme_font_size_override("font_size", 15); sub_msg.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		evbox.add_child(sub_msg)

		empty_panel.add_child(evbox)
		vbox.add_child(empty_panel)

	log_card.add_child(vbox)

func _undo_check_in(log_id: int) -> void:
	_dismiss_toast()
	if not db: return
	db.execute("DELETE FROM attendance_log WHERE id = ?;", [log_id])
	_refresh_dashboard()
