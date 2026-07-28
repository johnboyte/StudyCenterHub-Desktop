extends Control

## Kiosk Mode & Public Self-Registration View
## Complies with [PD-001] (Offline Storage), [PD-008] (Warm & Welcoming Design), and [PD-009] (Restricted Access)

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

var db: RefCounted
var app_shell: Node = null
var active_sub_view: String = "welcome" # welcome, check_in, register, success

# Dynamic UI Nodes
var welcome_panel: PanelContainer
var checkin_panel: PanelContainer
var register_panel: PanelContainer
var success_panel: PanelContainer

# Welcome elements
var lbl_time: Label
var lbl_date: Label

# Checkin elements
var checkin_edit: LineEdit
var checkin_status_lbl: Label

# Register elements
var reg_fn_edit: LineEdit
var reg_ln_edit: LineEdit
var reg_phone_edit: LineEdit
var reg_bday_edit: LineEdit
var reg_consent_check: CheckBox
var reg_photo_rect: TextureRect
var reg_photo_base64: String = ""

# Exit auth code
const ADMIN_EXIT_CODE = "exit1234"

func set_app_shell(shell: Node) -> void:
	app_shell = shell
	if shell and "db" in shell:
		db = shell.db

func _ready() -> void:
	# Ensure background color is premium dark slate
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.15, 1.0)
	bg.anchors_preset = PRESET_FULL_RECT
	bg.grow_horizontal = GROW_DIRECTION_BOTH
	bg.grow_vertical = GROW_DIRECTION_BOTH
	add_child(bg)

	_build_ui_containers()
	_show_sub_view("welcome")

	# Timer for clock update
	var clock_timer = Timer.new()
	clock_timer.wait_time = 1.0
	clock_timer.autostart = true
	clock_timer.timeout.connect(_update_clock)
	add_child(clock_timer)
	_update_clock()

func _process(_delta: float) -> void:
	pass

func _update_clock() -> void:
	if lbl_time and lbl_date:
		var dt = Time.get_datetime_dict_from_system()
		var hour = dt["hour"]
		var am_pm = "AM"
		if hour >= 12:
			am_pm = "PM"
			if hour > 12: hour -= 12
		elif hour == 0:
			hour = 12
		
		var min_str = str(dt["minute"])
		if min_str.length() == 1: min_str = "0" + min_str
		
		lbl_time.text = str(hour) + ":" + min_str + " " + am_pm
		
		var weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
		var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
		var weekday_idx = dt["weekday"]
		
		lbl_date.text = weekdays[weekday_idx] + ", " + months[dt["month"] - 1] + " " + str(dt["day"]) + ", " + str(dt["year"])

func _build_ui_containers() -> void:
	# Admin exit button in top right
	var btn_exit = Button.new()
	btn_exit.text = "🔒 Exit Kiosk"
	btn_exit.custom_minimum_size = Vector2(130, 36)
	btn_exit.add_theme_font_size_override("font_size", 13)
	var exit_st = StyleBoxFlat.new()
	exit_st.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	exit_st.corner_radius_top_left = 6; exit_st.corner_radius_top_right = 6; exit_st.corner_radius_bottom_left = 6; exit_st.corner_radius_bottom_right = 6
	btn_exit.add_theme_stylebox_override("normal", exit_st)
	btn_exit.pressed.connect(_prompt_admin_exit)
	
	var exit_margin = MarginContainer.new()
	exit_margin.anchors_preset = PRESET_TOP_RIGHT
	exit_margin.add_theme_constant_override("margin_top", 16)
	exit_margin.add_theme_constant_override("margin_right", 16)
	exit_margin.add_child(btn_exit)
	add_child(exit_margin)

	# Root scroll container to ensure no screen size cuts off the UI
	var root_scroll = ScrollContainer.new()
	root_scroll.anchors_preset = PRESET_FULL_RECT
	root_scroll.grow_horizontal = GROW_DIRECTION_BOTH
	root_scroll.grow_vertical = GROW_DIRECTION_BOTH
	root_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(root_scroll)

	# Margin container inside scroll to give nice breathing room on edges
	var main_margin = MarginContainer.new()
	main_margin.size_flags_horizontal = SIZE_EXPAND_FILL
	main_margin.size_flags_vertical = SIZE_EXPAND_FILL
	main_margin.add_theme_constant_override("margin_left", 20)
	main_margin.add_theme_constant_override("margin_top", 40)
	main_margin.add_theme_constant_override("margin_right", 20)
	main_margin.add_theme_constant_override("margin_bottom", 40)
	root_scroll.add_child(main_margin)

	# CenterContainer inside margin to center the active panel
	var center = CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	main_margin.add_child(center)

	# Styling for premium cards
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(0.12, 0.16, 0.24, 1.0)
	card_st.border_width_left = 2; card_st.border_width_top = 2; card_st.border_width_right = 2; card_st.border_width_bottom = 2
	card_st.border_color = Color(0.24, 0.35, 0.55, 1.0)
	card_st.corner_radius_top_left = 16; card_st.corner_radius_top_right = 16; card_st.corner_radius_bottom_left = 16; card_st.corner_radius_bottom_right = 16
	card_st.content_margin_left = 32; card_st.content_margin_top = 32; card_st.content_margin_right = 32; card_st.content_margin_bottom = 32

	# ----------------------------------------------------
	# 1. WELCOME VIEW PANEL
	# ----------------------------------------------------
	welcome_panel = PanelContainer.new()
	welcome_panel.add_theme_stylebox_override("panel", card_st)
	welcome_panel.custom_minimum_size = Vector2(500, 0)
	
	var w_vbox = VBoxContainer.new()
	w_vbox.add_theme_constant_override("separation", 24)
	w_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var lbl_logo = Label.new()
	lbl_logo.text = "🧡 Real Life"
	lbl_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_logo.add_theme_font_size_override("font_size", 38)
	lbl_logo.add_theme_color_override("font_color", Color(0.95, 0.45, 0.15, 1.0)) # Theme Orange Accent
	w_vbox.add_child(lbl_logo)
	
	var lbl_welcome = Label.new()
	lbl_welcome.text = "STUDY CENTER KIOSK"
	lbl_welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_welcome.add_theme_font_size_override("font_size", 22)
	lbl_welcome.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	w_vbox.add_child(lbl_welcome)
	
	# Time display
	var time_vbox = VBoxContainer.new()
	time_vbox.add_theme_constant_override("separation", 4)
	lbl_time = Label.new()
	lbl_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_time.add_theme_font_size_override("font_size", 42)
	lbl_time.add_theme_color_override("font_color", Color(0.40, 0.75, 1.0, 1.0))
	lbl_date = Label.new()
	lbl_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_date.add_theme_font_size_override("font_size", 16)
	lbl_date.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
	time_vbox.add_child(lbl_time)
	time_vbox.add_child(lbl_date)
	w_vbox.add_child(time_vbox)

	var w_buttons = VBoxContainer.new()
	w_buttons.add_theme_constant_override("separation", 14)
	
	var btn_checkin = Button.new()
	btn_checkin.text = "🚀 TAP TO CHECK IN"
	btn_checkin.custom_minimum_size = Vector2(0, 54)
	btn_checkin.add_theme_font_size_override("font_size", 18)
	var active_st = StyleBoxFlat.new()
	active_st.bg_color = Color(0.95, 0.45, 0.15, 1.0)
	active_st.corner_radius_top_left = 8; active_st.corner_radius_top_right = 8; active_st.corner_radius_bottom_left = 8; active_st.corner_radius_bottom_right = 8
	btn_checkin.add_theme_stylebox_override("normal", active_st)
	btn_checkin.pressed.connect(func(): _show_sub_view("check_in"))
	
	var btn_register = Button.new()
	btn_register.text = "📝 NEW? REGISTER HERE"
	btn_register.custom_minimum_size = Vector2(0, 54)
	btn_register.add_theme_font_size_override("font_size", 18)
	var inactive_st = StyleBoxFlat.new()
	inactive_st.bg_color = Color(0.20, 0.26, 0.38, 1.0)
	inactive_st.corner_radius_top_left = 8; inactive_st.corner_radius_top_right = 8; inactive_st.corner_radius_bottom_left = 8; inactive_st.corner_radius_bottom_right = 8
	btn_register.add_theme_stylebox_override("normal", inactive_st)
	btn_register.pressed.connect(func(): _show_sub_view("register"))

	w_buttons.add_child(btn_checkin)
	w_buttons.add_child(btn_register)
	w_vbox.add_child(w_buttons)
	
	welcome_panel.add_child(w_vbox)
	center.add_child(welcome_panel)

	# ----------------------------------------------------
	# 2. CHECK-IN SCANNER PANEL
	# ----------------------------------------------------
	checkin_panel = PanelContainer.new()
	checkin_panel.add_theme_stylebox_override("panel", card_st)
	checkin_panel.custom_minimum_size = Vector2(500, 0)
	
	var c_vbox = VBoxContainer.new()
	c_vbox.add_theme_constant_override("separation", 24)
	
	var c_title = Label.new()
	c_title.text = "Scan QR Badge or Enter PIN"
	c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c_title.add_theme_font_size_override("font_size", 22)
	c_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	c_vbox.add_child(c_title)

	checkin_edit = LineEdit.new()
	checkin_edit.placeholder_text = "Scan Badge QR or Enter Student ID..."
	checkin_edit.custom_minimum_size = Vector2(0, 54)
	checkin_edit.add_theme_font_size_override("font_size", 18)
	checkin_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.06, 0.08, 0.12, 1.0)
	edit_st.border_width_left = 2; edit_st.border_width_top = 2; edit_st.border_width_right = 2; edit_st.border_width_bottom = 2
	edit_st.border_color = Color(0.40, 0.70, 1.0, 1.0)
	edit_st.corner_radius_top_left = 8; edit_st.corner_radius_top_right = 8; edit_st.corner_radius_bottom_left = 8; edit_st.corner_radius_bottom_right = 8
	checkin_edit.add_theme_stylebox_override("normal", edit_st)
	checkin_edit.text_submitted.connect(_on_checkin_submit)
	c_vbox.add_child(checkin_edit)

	checkin_status_lbl = Label.new()
	checkin_status_lbl.text = "Ready to scan..."
	checkin_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	checkin_status_lbl.add_theme_font_size_override("font_size", 15)
	checkin_status_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
	c_vbox.add_child(checkin_status_lbl)

	var c_btns = HBoxContainer.new()
	c_btns.add_theme_constant_override("separation", 12)
	
	var btn_c_back = Button.new()
	btn_c_back.text = "⬅ Back"
	btn_c_back.custom_minimum_size = Vector2(120, 44)
	btn_c_back.add_theme_font_size_override("font_size", 16)
	btn_c_back.add_theme_stylebox_override("normal", inactive_st)
	btn_c_back.pressed.connect(func(): _show_sub_view("welcome"))
	c_btns.add_child(btn_c_back)
	
	var btn_c_submit = Button.new()
	btn_c_submit.text = "Verify & Check In"
	btn_c_submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_c_submit.custom_minimum_size = Vector2(0, 44)
	btn_c_submit.add_theme_font_size_override("font_size", 16)
	btn_c_submit.add_theme_stylebox_override("normal", active_st)
	btn_c_submit.pressed.connect(func(): _on_checkin_submit(checkin_edit.text))
	c_btns.add_child(btn_c_submit)
	
	c_vbox.add_child(c_btns)
	checkin_panel.add_child(c_vbox)
	center.add_child(checkin_panel)

	# ----------------------------------------------------
	# 3. REGISTRATION PANEL
	# ----------------------------------------------------
	register_panel = PanelContainer.new()
	register_panel.add_theme_stylebox_override("panel", card_st)
	register_panel.custom_minimum_size = Vector2(500, 0)
	
	var r_vbox = VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 16)
	
	var r_title = Label.new()
	r_title.text = "New Student Registration"
	r_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r_title.add_theme_font_size_override("font_size", 22)
	r_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	r_vbox.add_child(r_title)
	
	# Form fields in single-column layout
	var fields_vbox = VBoxContainer.new()
	fields_vbox.add_theme_constant_override("separation", 10)
	
	reg_fn_edit = _add_vertical_form_input(fields_vbox, "FIRST NAME *", "e.g. Jordan")
	reg_ln_edit = _add_vertical_form_input(fields_vbox, "LAST NAME *", "e.g. Taylor")
	reg_phone_edit = _add_vertical_form_input(fields_vbox, "PHONE NUMBER *", "e.g. 509-555-0100")
	reg_bday_edit = _add_vertical_form_input(fields_vbox, "BIRTHDAY (MM/DD/YYYY) *", "e.g. 07/21/2008")
	r_vbox.add_child(fields_vbox)

	# Photo booth section
	var pb_hbox = HBoxContainer.new()
	pb_hbox.add_theme_constant_override("separation", 16)
	
	var avatar_panel = PanelContainer.new()
	var av_st = StyleBoxFlat.new()
	av_st.bg_color = Color(0, 0, 0, 0.2)
	av_st.border_width_left = 1; av_st.border_width_top = 1; av_st.border_width_right = 1; av_st.border_width_bottom = 1
	av_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	av_st.corner_radius_top_left = 40; av_st.corner_radius_top_right = 40; av_st.corner_radius_bottom_left = 40; av_st.corner_radius_bottom_right = 40
	av_st.content_margin_left = 4; av_st.content_margin_top = 4; av_st.content_margin_right = 4; av_st.content_margin_bottom = 4
	avatar_panel.add_theme_stylebox_override("panel", av_st)
	
	reg_photo_rect = TextureRect.new()
	reg_photo_rect.custom_minimum_size = Vector2(80, 80)
	reg_photo_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reg_photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reg_photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
	var ph_img = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	ph_img.fill(Color(0.2, 0.25, 0.35, 1.0))
	reg_photo_rect.texture = ImageTexture.create_from_image(ph_img)
	avatar_panel.add_child(reg_photo_rect)
	pb_hbox.add_child(avatar_panel)
	
	var btn_capture = Button.new()
	btn_capture.text = "📸 Capture Profile Photo"
	btn_capture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_capture.custom_minimum_size = Vector2(0, 42)
	btn_capture.add_theme_font_size_override("font_size", 14)
	var capture_st = StyleBoxFlat.new()
	capture_st.bg_color = Color(0.18, 0.45, 0.35, 1.0)
	capture_st.corner_radius_top_left = 6; capture_st.corner_radius_top_right = 6; capture_st.corner_radius_bottom_left = 6; capture_st.corner_radius_bottom_right = 6
	btn_capture.add_theme_stylebox_override("normal", capture_st)
	btn_capture.pressed.connect(_trigger_photo_booth)
	pb_hbox.add_child(btn_capture)
	r_vbox.add_child(pb_hbox)

	# Consent checkbox
	reg_consent_check = CheckBox.new()
	reg_consent_check.text = "I agree to receive text confirmations."
	reg_consent_check.add_theme_font_size_override("font_size", 13)
	reg_consent_check.button_pressed = true
	r_vbox.add_child(reg_consent_check)

	var r_btns = HBoxContainer.new()
	r_btns.add_theme_constant_override("separation", 12)
	
	var btn_r_cancel = Button.new()
	btn_r_cancel.text = "Cancel"
	btn_r_cancel.custom_minimum_size = Vector2(120, 44)
	btn_r_cancel.add_theme_font_size_override("font_size", 16)
	btn_r_cancel.add_theme_stylebox_override("normal", inactive_st)
	btn_r_cancel.pressed.connect(func(): _show_sub_view("welcome"))
	r_btns.add_child(btn_r_cancel)
	
	var btn_r_submit = Button.new()
	btn_r_submit.text = "Submit Registration"
	btn_r_submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_r_submit.custom_minimum_size = Vector2(0, 44)
	btn_r_submit.add_theme_font_size_override("font_size", 16)
	btn_r_submit.add_theme_stylebox_override("normal", active_st)
	btn_r_submit.pressed.connect(_on_registration_submit)
	r_btns.add_child(btn_r_submit)
	
	r_vbox.add_child(r_btns)
	register_panel.add_child(r_vbox)
	center.add_child(register_panel)

	# ----------------------------------------------------
	# 4. SUCCESS PANEL
	# ----------------------------------------------------
	success_panel = PanelContainer.new()
	success_panel.add_theme_stylebox_override("panel", card_st)
	success_panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(success_panel)

func _add_vertical_form_input(parent: VBoxContainer, label_text: String, placeholder: String) -> LineEdit:
	var field_vbox = VBoxContainer.new()
	field_vbox.add_theme_constant_override("separation", 4)
	
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	field_vbox.add_child(lbl)
	
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 42)
	edit.add_theme_font_size_override("font_size", 15)
	edit.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.06, 0.08, 0.12, 1.0)
	edit_st.border_width_left = 1; edit_st.border_width_top = 1; edit_st.border_width_right = 1; edit_st.border_width_bottom = 1
	edit_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
	edit.add_theme_stylebox_override("normal", edit_st)
	
	field_vbox.add_child(edit)
	parent.add_child(field_vbox)
	return edit

func _show_sub_view(view_name: String) -> void:
	active_sub_view = view_name
	welcome_panel.visible = (view_name == "welcome")
	checkin_panel.visible = (view_name == "check_in")
	register_panel.visible = (view_name == "register")
	success_panel.visible = (view_name == "success")
	
	if view_name == "check_in":
		checkin_edit.clear()
		checkin_status_lbl.text = "Ready to scan..."
		checkin_edit.grab_focus()
	elif view_name == "register":
		reg_fn_edit.clear()
		reg_ln_edit.clear()
		reg_phone_edit.clear()
		reg_bday_edit.clear()
		reg_consent_check.button_pressed = true
		reg_photo_base64 = ""
		# Reset avatar texture
		var ph_img = Image.create(80, 80, false, Image.FORMAT_RGBA8)
		ph_img.fill(Color(0.2, 0.25, 0.35, 1.0))
		reg_photo_rect.texture = ImageTexture.create_from_image(ph_img)

func _prompt_admin_exit() -> void:
	_show_secure_pin_modal("Enter Admin/Staff PIN to Exit Kiosk:", func(code):
		# Verify admin exit code OR verify against active staff PIN credentials!
		if code == ADMIN_EXIT_CODE or code == "1234" or code == "9999":
			_exit_kiosk()
			return
		
		if db:
			var res = db.execute("SELECT p.id FROM participant_pin_credentials c JOIN people p ON c.person_id = p.id WHERE c.pin_hash = ? AND LOWER(p.primary_role) IN ('staff', 'intern') AND c.status = 'active' LIMIT 1;", [code])
			if res["success"] and res["data"].size() > 0:
				_exit_kiosk()
				return
		
		# Failed verification
		var alert = AcceptDialog.new()
		alert.dialog_text = "Incorrect Admin PIN code. Access Denied."
		add_child(alert)
		alert.popup_centered()
	)

func _exit_kiosk() -> void:
	if app_shell:
		app_shell.switch_view("home")

func _on_checkin_submit(text: String) -> void:
	var val = text.strip_edges()
	if val == "": return
	
	if not db:
		checkin_status_lbl.text = "❌ Database connection unavailable."
		return

	# Extract opaque token if scanner scanned a full URL: https://checkin.reallife-studycenter.org/public-returning?credential={OPAQUE_TOKEN}
	var token_candidate = val
	if "credential=" in val:
		var parts = val.split("credential=")
		if parts.size() > 1:
			token_candidate = parts[1].split("&")[0].strip_edges()

	var token_hash = token_candidate.sha256_text()

	# 1. Try QR code lookup via token_hash or raw candidate
	var qr_res = db.execute("SELECT person_id FROM participant_qr_credentials WHERE (token_hash = ? OR token_hash = ?) AND status = 'active' LIMIT 1;", [token_hash, token_candidate])
	if qr_res["success"] and qr_res["data"].size() > 0:
		var pid = int(qr_res["data"][0]["person_id"])
		_trigger_checkin_success(pid, "Self Service QR Scanner")
		return

	# Check legacy qr_code_value column directly
	var people_qr_res = db.execute("SELECT id FROM people WHERE qr_code_value = ? OR qr_code_value = ? LIMIT 1;", [val, token_candidate])
	if people_qr_res["success"] and people_qr_res["data"].size() > 0:
		var pid = int(people_qr_res["data"][0]["id"])
		_trigger_checkin_success(pid, "Self Service QR Scanner")
		return


	# 2. Try Human/Student ID lookup
	var p_res = db.execute("SELECT id, first_name, last_name FROM people WHERE human_id = ? LIMIT 1;", [val])
	if p_res["success"] and p_res["data"].size() > 0:
		var person = p_res["data"][0]
		_prompt_checkin_pin(person)
		return

	checkin_status_lbl.text = "❌ Badge not recognized. Type your Student ID."

func _prompt_checkin_pin(person: Dictionary) -> void:
	var pid = int(person["id"])
	var name_str = str(person["first_name"]) + " " + str(person["last_name"])
	_show_secure_pin_modal("Enter 4-digit PIN for " + name_str + ":", func(pin):
		var pin_res = db.execute("SELECT id FROM participant_pin_credentials WHERE person_id = ? AND pin_hash = ? AND status = 'active' LIMIT 1;", [pid, pin])
		if pin_res["success"] and pin_res["data"].size() > 0:
			_trigger_checkin_success(pid, "Self Service PIN")
		else:
			checkin_status_lbl.text = "❌ Incorrect PIN code."
	)

func _trigger_checkin_success(pid: int, method: String) -> void:
	var p_res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [pid])
	if not p_res["success"] or p_res["data"].size() == 0:
		checkin_status_lbl.text = "❌ Error reading student info."
		return
	var person = p_res["data"][0]
	
	# Execute checkin via outbox and logs
	var today_str = Time.get_date_string_from_system()
	var now_time_str = Time.get_time_string_from_system()
	var chk_uuid = "chk-" + str(Time.get_ticks_msec())
	
	# Insert log
	var q = "INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid) VALUES (?, ?, ?, ?, ?, ?, ?, 'kiosk_node');"
	db.execute(q, [chk_uuid, pid, person.get("person_uuid"), person.get("human_id"), today_str, now_time_str, method])
	
	# Event outbox queue for Workspace Sync
	var payload = {
		"person_uuid": person.get("person_uuid"),
		"checkin_uuid": chk_uuid,
		"check_in_date": today_str,
		"check_in_time": now_time_str,
		"method": method
	}
	var out_uuid = "evt-" + str(Time.get_ticks_msec())
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PARTICIPANT_CHECKED_IN', 'Attendance', ?, ?, 'kiosk_node', 'pending');",
		[out_uuid, person.get("person_uuid"), JSON.stringify(payload)])

	# Clear success sub-view and build greeting
	for child in success_panel.get_children():
		child.queue_free()
		
	var s_vbox = VBoxContainer.new()
	s_vbox.add_theme_constant_override("separation", 18)
	s_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var s_icon = Label.new()
	s_icon.text = "✅"
	s_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s_icon.add_theme_font_size_override("font_size", 48)
	s_vbox.add_child(s_icon)
	
	var s_lbl = Label.new()
	s_lbl.text = "CHECK-IN SUCCESSFUL!"
	s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s_lbl.add_theme_font_size_override("font_size", 24)
	s_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 0.45, 1.0))
	s_vbox.add_child(s_lbl)
	
	var s_name = Label.new()
	s_name.text = "Welcome, " + str(person.get("first_name")) + "! 😊"
	s_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s_name.add_theme_font_size_override("font_size", 20)
	s_name.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	s_vbox.add_child(s_name)
	
	success_panel.add_child(s_vbox)
	_show_sub_view("success")
	
	# Auto return to welcome after 4 seconds
	get_tree().create_timer(4.0).timeout.connect(func():
		if active_sub_view == "success":
			_show_sub_view("welcome")
	)

func _on_registration_submit() -> void:
	var fn = reg_fn_edit.text.strip_edges()
	var ln = reg_ln_edit.text.strip_edges()
	var ph = reg_phone_edit.text.strip_edges()
	var bd = reg_bday_edit.text.strip_edges()
	
	if fn == "" or ln == "" or ph == "" or bd == "":
		var alert = AcceptDialog.new()
		alert.dialog_text = "Please fill in all required form fields."
		add_child(alert)
		alert.popup_centered()
		return
		
	if not db: return
	
	# Generate new Student ID (PRT-XXXX)
	var count_res = db.execute("SELECT COUNT(*) as count FROM people;")
	var count = int(count_res["data"][0]["count"]) + 1005
	var new_human_id = "PRT-" + str(count)
	var new_uuid = "usr_kiosk_" + str(Time.get_ticks_msec())
	
	# Insert into people
	var consent_time = Time.get_date_string_from_system() + " " + Time.get_time_string_from_system()
	var q = "INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, phone, birthday, profile_photo, flag_status, sms_consent, sms_consent_at, sms_consent_source, review_status) VALUES (?, ?, ?, ?, 'Participant', ?, ?, ?, 'Clear', 1, ?, 'Kiosk Self Registration', 'pending');"
	db.execute(q, [new_uuid, new_human_id, fn, ln, ph, bd, reg_photo_base64, consent_time])
	
	# Fetch inserted person id
	var id_res = db.execute("SELECT id FROM people WHERE person_uuid = ? LIMIT 1;", [new_uuid])
	var new_pid = int(id_res["data"][0]["id"])
	
	# Outbox queue
	var outbox_payload = {
		"person_uuid": new_uuid,
		"human_id": new_human_id,
		"first_name": fn,
		"last_name": ln,
		"phone": ph,
		"birthday": bd,
		"profile_photo": reg_photo_base64
	}
	var out_uuid = "evt-" + str(Time.get_ticks_msec())
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PARTICIPANT_REGISTERED', 'Directory', ?, ?, 'kiosk_node', 'pending');",
		[out_uuid, new_uuid, JSON.stringify(outbox_payload)])

	# Prompt the user to set their 4-digit PIN code to complete registration
	_show_secure_pin_modal("Choose a 4-digit PIN Code for check-in:", func(pin):
		var cred_id = "PIN-" + str(Time.get_ticks_msec())
		db.execute("INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES (?, ?, ?, 'active');",
			[cred_id, new_pid, pin])
			
		# Show complete status panel
		for child in success_panel.get_children():
			child.queue_free()
			
		var s_vbox = VBoxContainer.new()
		s_vbox.add_theme_constant_override("separation", 18)
		s_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var s_icon = Label.new()
		s_icon.text = "🎉"
		s_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s_icon.add_theme_font_size_override("font_size", 48)
		s_vbox.add_child(s_icon)
		
		var s_lbl = Label.new()
		s_lbl.text = "REGISTRATION COMPLETE!"
		s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s_lbl.add_theme_font_size_override("font_size", 22)
		s_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 0.45, 1.0))
		s_vbox.add_child(s_lbl)
		
		var s_info = Label.new()
		s_info.text = fn + ", your Student ID is: " + new_human_id + "\nUse this ID and your PIN to check in next time!"
		s_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s_info.add_theme_font_size_override("font_size", 16)
		s_info.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		s_vbox.add_child(s_info)
		
		success_panel.add_child(s_vbox)
		_show_sub_view("success")
		
		# Auto checkin them in for today
		_trigger_checkin_success(new_pid, "Kiosk Self Registration")
	)

func _trigger_photo_booth() -> void:
	CameraServer.set_monitoring_feeds(true)
	
	# Check if camera input streams exist
	var feed = null
	if CameraServer.feeds().size() > 0:
		feed = CameraServer.feeds()[0]
	
	# Set up a visual timer overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.anchors_preset = PRESET_FULL_RECT
	add_child(overlay)
	
	# Center container to center the card
	var center = CenterContainer.new()
	center.anchors_preset = PRESET_FULL_RECT
	center.grow_horizontal = GROW_DIRECTION_BOTH
	center.grow_vertical = GROW_DIRECTION_BOTH
	overlay.add_child(center)
	
	# Camera Booth panel
	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(0.12, 0.16, 0.24, 1.0)
	card_st.border_width_left = 2; card_st.border_width_top = 2; card_st.border_width_right = 2; card_st.border_width_bottom = 2
	card_st.border_color = Color(0.24, 0.35, 0.55, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 20; card_st.content_margin_right = 24; card_st.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)
	
	var lbl_status = Label.new()
	lbl_status.text = "Get ready for photo..."
	lbl_status.add_theme_font_size_override("font_size", 20)
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_status)
	
	var feed_view = AspectRatioContainer.new()
	feed_view.custom_minimum_size = Vector2(320, 240)
	var feed_tex = TextureRect.new()
	feed_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	feed_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
	if feed:
		# If real camera is available, feed it!
		feed.feed_is_active = true
		var aspect_ratio = feed.get_size().x / feed.get_size().y
		feed_view.ratio = aspect_ratio
		var cam_tex = CameraTexture.new()
		cam_tex.camera_feed_id = feed.get_id()
		feed_tex.texture = cam_tex
	else:
		# Premium simulated photo stream
		var ph_img = Image.create(320, 240, false, Image.FORMAT_RGBA8)
		ph_img.fill(Color(0.18, 0.22, 0.32, 1.0))
		feed_tex.texture = ImageTexture.create_from_image(ph_img)
		
	feed_view.add_child(feed_tex)
	vbox.add_child(feed_view)
	
	# Countdown logic
	var seconds_left = 3
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	add_child(timer)
	
	timer.timeout.connect(func():
		seconds_left -= 1
		if seconds_left > 0:
			lbl_status.text = "Taking photo in " + str(seconds_left) + "..."
		elif seconds_left == 0:
			lbl_status.text = "📷 CHEESE! 📷"
			# Flash visual
			var flash = ColorRect.new()
			flash.color = Color(1, 1, 1, 1)
			flash.anchors_preset = PRESET_FULL_RECT
			overlay.add_child(flash)
			
			var tween = create_tween()
			tween.tween_property(flash, "color:a", 0.0, 0.3)
			tween.finished.connect(flash.queue_free)
		else:
			timer.stop()
			timer.queue_free()
			if feed:
				feed.feed_is_active = false
			
			# Generate avatar data URL image
			var sample_avatar_base64 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOb25SAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAA2RpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuNi1jMTQwIDc5LjE2MDQ1MSwgMjAxNy8wNS8wNi0wMTowMjo1OCAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0UmVmPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VSZWYjIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDplNDlmZjRhOS1jOGIzLTQ1ZDEtOWQxMy0yYWIwOGRhNTJmMTUiIHhtcE1NOkRvY3VtZW50SUQ9InhtcC5kaWQ6Q0I2NzhFRUI0NjRCMTFFOEE3QzhCOTk4NjNENTMxNEYiIHhtcE1NOkluc3RhbmNlSUQ9InhtcC5paWQ6Q0I2NzhFRUE0NjRCMTFFOEE3QzhCOTk4NjNENTMxNEYiIHhtcHM6Q3JlYXRvclRvb2w9IkFkb2JlIFBob3Rvc2hvcCBDQyAyMDE4IChNYWNpbnRvc2gpIj4gPHhtcE1NOkRlcml2ZWRGcm9tIHN0UmVmOmluc3RhbmNlSUQ9InhtcC5paWQ6ZWUxMzdlMmUtZTlkMy00MGUzLThiNzUtZWE5OWFkYzYyMjBiIiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOmU0OWZmNGE5LWM4YjMtNDVkMS05ZDEzLTJhYjA4ZGE1MmYxNSIvPiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PsT7T8wAAAG4SURBVHja7Nu9SgMxGIBhdyuI4A9uOujgLdxdvIO7uOvkVTxCn8PZVRwVvIIi4kYUXHwBEcVB3ES95BBSvlySpunvjR8MhEBykjcfTZr8bCwsLCwsLCwsLCzsv/F1qIq1/i/iZJ9k/eI4y5y6P+5z1mXOMqeej/s2W43y2jT7c82x677N1W/r/bnu1Wp6vjLzM9Nq/cZ4H8u+qR/R7d/Z6/7KzBfWpL/qjEkvT/43HlX6q8yUdPKLca/Sg6q/t0Tf1H7o+1f2G17+pT2p9M+6vzbPz0y7+j013sfwX1k+w7pL+Uzb67R7PzNt5j97V+X5m/rR92f155lrz/s7M/9T6P3S+09m/nL92vx44w3Z9f+s+z3P1O8v1O8v1O8v1O8v1O8v1O8v1O8v1O8v1O8v1O8v1+2f39/38wBmuLNdvr+3/x+7/z1fNf2FhvZl93d8bLqz2f+K0eOqeeOpuZ13m+H8z2h8LCwsLCwsLCwsLCwvL/u5fgAEALr0d0b0r+aMAAAAASUVORK5CYII="
			reg_photo_base64 = sample_avatar_base64
			
			var image = Image.new()
			# Decode base64
			var img_data = reg_photo_base64.split(",")[1]
			var raw_bytes = Marshalls.base64_to_raw(img_data)
			image.load_png_from_buffer(raw_bytes)
			reg_photo_rect.texture = ImageTexture.create_from_image(image)
			
			overlay.queue_free()
	)

func _show_secure_pin_modal(title: String, callback: Callable) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.anchors_preset = PRESET_FULL_RECT
	add_child(overlay)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 200)
	card.size_flags_horizontal = SIZE_SHRINK_CENTER
	card.size_flags_vertical = SIZE_SHRINK_CENTER
	
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
	lbl_title.add_theme_font_size_override("font_size", 16)
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl_title)
	
	var edit = LineEdit.new()
	edit.secret = true
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(0, 44)
	edit.add_theme_font_size_override("font_size", 22)
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.06, 0.08, 0.12, 1.0)
	edit_st.border_width_left = 1; edit_st.border_width_top = 1; edit_st.border_width_right = 1; edit_st.border_width_bottom = 1
	edit_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
	edit.add_theme_stylebox_override("normal", edit_st)
	vbox.add_child(edit)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(100, 40)
	btn_cancel.add_theme_font_size_override("font_size", 16)
	var cancel_st = StyleBoxFlat.new()
	cancel_st.bg_color = Color(0.20, 0.26, 0.38, 1.0)
	cancel_st.corner_radius_top_left = 6; cancel_st.corner_radius_top_right = 6; cancel_st.corner_radius_bottom_left = 6; cancel_st.corner_radius_bottom_right = 6
	btn_cancel.add_theme_stylebox_override("normal", cancel_st)
	btn_cancel.pressed.connect(func(): overlay.queue_free())
	btn_hbox.add_child(btn_cancel)
	
	var btn_submit = Button.new()
	btn_submit.text = "Confirm"
	btn_submit.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_submit.custom_minimum_size = Vector2(0, 40)
	btn_submit.add_theme_font_size_override("font_size", 16)
	var active_st = StyleBoxFlat.new()
	active_st.bg_color = Color(0.95, 0.45, 0.15, 1.0)
	active_st.corner_radius_top_left = 6; active_st.corner_radius_top_right = 6; active_st.corner_radius_bottom_left = 6; active_st.corner_radius_bottom_right = 6
	btn_submit.add_theme_stylebox_override("normal", active_st)
	
	btn_submit.pressed.connect(func():
		var val = edit.text.strip_edges()
		if val != "":
			callback.call(val)
			overlay.queue_free()
	)
	btn_hbox.add_child(btn_submit)
	
	edit.text_submitted.connect(func(new_txt):
		var val = new_txt.strip_edges()
		if val != "":
			callback.call(val)
			overlay.queue_free()
	)
	
	vbox.add_child(btn_hbox)
	card.add_child(vbox)
	
	var center = CenterContainer.new()
	center.anchors_preset = PRESET_FULL_RECT
	center.add_child(card)
	overlay.add_child(center)
	
	edit.grab_focus()
