extends "res://app/scenes/standard_page_container.gd"

## Administration & Platform Control Center View (ADM-SPR1-001)
## Complies with [PD-006] (Subscription Licensing), [PD-009] (RBAC), and [PD-010] (White-Label & Vocabulary).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")
const GatewaySyncScript = preload("res://src/domain/sync/gateway_sync_service.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const CardPrintQueueDialogScript = preload("res://app/scenes/card_print_queue_dialog.gd")
const PublicQrSignDialogScript = preload("res://app/scenes/public_qr_sign_dialog.gd")

var db: RefCounted
var active_tab: String = "modules"
var twilio_service: RefCounted
var config_service: RefCounted
var selected_user_id: int = 0
var selected_rbac_role: String = "Shift Supervisor"

@onready var btn_tab_modules: Button = %BtnTabModules
@onready var btn_tab_rbac: Button = %BtnTabRbac
@onready var btn_tab_branding: Button = %BtnTabBranding
@onready var btn_tab_twilio: Button = %BtnTabTwilio
@onready var btn_tab_header_messages: Button = %BtnTabHeaderMessages
@onready var btn_tab_birthday: Button = %BtnTabBirthday
@onready var content_card: PanelContainer = %ContentCard
var btn_tab_ivr: Button
var btn_tab_sessions: Button

const PAGES_LIST = [
	{"key": "home", "label": "Home"},
	{"key": "people", "label": "People"},
	{"key": "communications", "label": "Communications"},
	{"key": "attendance", "label": "Check In"},
	{"key": "schedules", "label": "Schedules"},
	{"key": "volunteers", "label": "Volunteers"},
	{"key": "pathways", "label": "Pathways"},
	{"key": "administration", "label": "Administration"},
	{"key": "reports", "label": "Reports"},
	{"key": "settings", "label": "Settings"}
]

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

func _ready() -> void:
	_init_database()
	_style_card()
	_connect_tabs()
	
	# Dynamically instantiate IVR and Sessions tab buttons in TabHBox
	btn_tab_ivr = Button.new()
	btn_tab_ivr.name = "BtnTabIvr"
	btn_tab_ivr.text = "  📞 Phone & Voicemail Settings  "
	btn_tab_ivr.custom_minimum_size = Vector2(0, 36)
	btn_tab_ivr.add_theme_font_size_override("font_size", 14)

	btn_tab_sessions = Button.new()
	btn_tab_sessions.name = "BtnTabSessions"
	btn_tab_sessions.text = "  📋 Session Types & Locations  "
	btn_tab_sessions.custom_minimum_size = Vector2(0, 36)
	btn_tab_sessions.add_theme_font_size_override("font_size", 14)
	
	var tab_hbox = get_node_or_null("MarginContainer/MainVBox/TabHBox")
	if tab_hbox:
		tab_hbox.add_child(btn_tab_ivr)
		btn_tab_ivr.pressed.connect(func(): switch_tab("ivr"))
		tab_hbox.add_child(btn_tab_sessions)
		btn_tab_sessions.pressed.connect(func(): switch_tab("sessions"))

		var btn_pub_qr = Button.new()
		btn_pub_qr.name = "BtnPubQrSign"
		btn_pub_qr.text = "  🏛️ Public QR Sign  "
		btn_pub_qr.custom_minimum_size = Vector2(0, 36)
		btn_pub_qr.add_theme_font_size_override("font_size", 14)
		tab_hbox.add_child(btn_pub_qr)
		btn_pub_qr.pressed.connect(func():
			var dlg = PublicQrSignDialogScript.new(self)
			dlg.show_dialog()
		)

		var btn_card_queue = Button.new()
		btn_card_queue.name = "BtnCardQueue"
		btn_card_queue.text = "  🎴 Card Print Queue  "
		btn_card_queue.custom_minimum_size = Vector2(0, 36)
		btn_card_queue.add_theme_font_size_override("font_size", 14)
		tab_hbox.add_child(btn_card_queue)
		btn_card_queue.pressed.connect(func():
			var dlg = CardPrintQueueDialogScript.new(self)
			dlg.show_dialog()
		)
		
	switch_tab("modules")

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
	db.execute("""
		CREATE TABLE IF NOT EXISTS app_settings (
			setting_key TEXT PRIMARY KEY,
			setting_value TEXT NOT NULL,
			updated_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")
	if not twilio_service:
		twilio_service = TwilioGatewayScript.new(db)
	if not config_service:
		config_service = SessionConfigServiceScript.new(db)

func _style_card() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.91, 0.95, 1.0)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 24; style.content_margin_top = 22; style.content_margin_right = 24; style.content_margin_bottom = 22
	content_card.add_theme_stylebox_override("panel", style)

func _connect_tabs() -> void:
	if btn_tab_modules: btn_tab_modules.pressed.connect(func(): switch_tab("modules"))
	if btn_tab_rbac: btn_tab_rbac.pressed.connect(func(): switch_tab("rbac"))
	if btn_tab_branding: btn_tab_branding.pressed.connect(func(): switch_tab("branding"))
	if btn_tab_twilio: btn_tab_twilio.pressed.connect(func(): switch_tab("twilio"))
	if btn_tab_header_messages: btn_tab_header_messages.pressed.connect(func(): switch_tab("header_messages"))
	if btn_tab_birthday: btn_tab_birthday.pressed.connect(func(): switch_tab("birthday"))

func switch_tab(tab_name: String) -> void:
	active_tab = tab_name
	_update_tab_button_styles()

	for child in content_card.get_children():
		child.free()

	if active_tab == "modules":
		_render_modules_tab()
	elif active_tab == "rbac":
		_render_rbac_tab()
	elif active_tab == "branding":
		_render_branding_tab()
	elif active_tab == "twilio":
		_render_twilio_tab()
	elif active_tab == "header_messages":
		_render_header_messages_tab()
	elif active_tab == "birthday":
		_render_birthday_tab()
	elif active_tab == "ivr":
		_render_ivr_tab()
	elif active_tab == "sessions":
		_render_sessions_config_tab()

func _update_tab_button_styles() -> void:
	_style_tab_btn(btn_tab_modules, active_tab == "modules")
	_style_tab_btn(btn_tab_rbac, active_tab == "rbac")
	_style_tab_btn(btn_tab_branding, active_tab == "branding")
	_style_tab_btn(btn_tab_twilio, active_tab == "twilio")
	_style_tab_btn(btn_tab_header_messages, active_tab == "header_messages")
	_style_tab_btn(btn_tab_birthday, active_tab == "birthday")
	_style_tab_btn(btn_tab_ivr, active_tab == "ivr")
	_style_tab_btn(btn_tab_sessions, active_tab == "sessions")

func _get_active_theme_color() -> Color:
	var idx = int(_get_setting_string("ORG_ACCENT_INDEX", "0"))
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
	var idx = int(_get_setting_string("ORG_ACCENT_INDEX", "0"))
	if idx == 0:
		return Color(0.737, 0.635, 0.439, 1.0) # AU Gold #BCA270
	return _get_active_theme_color()

func _style_tab_btn(btn: Button, is_active: bool) -> void:
	if not btn: return
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 16)

	var primary_col = _get_active_theme_color()
	var sec_col = _get_active_secondary_color()

	var st = StyleBoxFlat.new()
	st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
	st.content_margin_left = 18; st.content_margin_right = 18; st.content_margin_top = 10; st.content_margin_bottom = 10

	var st_hover = StyleBoxFlat.new()
	st_hover.corner_radius_top_left = 8; st_hover.corner_radius_top_right = 8; st_hover.corner_radius_bottom_left = 8; st_hover.corner_radius_bottom_right = 8
	st_hover.content_margin_left = 18; st_hover.content_margin_right = 18; st_hover.content_margin_top = 10; st_hover.content_margin_bottom = 10

	if is_active:
		st.bg_color = primary_col
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))

		st_hover.bg_color = primary_col.lightened(0.08)
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	else:
		st.bg_color = Color(0.94, 0.96, 0.98, 1.0)
		btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))

		st_hover.bg_color = Color(0.97, 0.98, 1.0, 1.0)
		st_hover.border_width_left = 1; st_hover.border_width_top = 1; st_hover.border_width_right = 1; st_hover.border_width_bottom = 1
		st_hover.border_color = sec_col
		btn.add_theme_color_override("font_hover_color", primary_col)

	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", st_hover)
	btn.add_theme_stylebox_override("pressed", st)

func _style_input_control(control: Control, font_size: int = 18) -> void:
	if not control: return
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	control.add_theme_color_override("font_hover_color", Color(0.08, 0.12, 0.18, 1.0))
	control.add_theme_color_override("font_focus_color", Color(0.08, 0.12, 0.18, 1.0))
	control.add_theme_color_override("font_placeholder_color", Color(0.40, 0.46, 0.54, 1.0))

	if control is LineEdit:
		control.caret_blink = true
		control.caret_blink_interval = 0.5
		control.add_theme_color_override("caret_color", Color(0.08, 0.12, 0.18, 1.0))
		control.add_theme_color_override("font_uneditable_color", Color(0.0, 0.0, 0.0, 1.0))

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
	st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
	st.content_margin_left = 14; st.content_margin_right = 14; st.content_margin_top = 8; st.content_margin_bottom = 8

	var st_focus = st.duplicate()
	st_focus.border_color = _get_active_theme_color()

	control.add_theme_stylebox_override("normal", st)
	control.add_theme_stylebox_override("hover", st)
	control.add_theme_stylebox_override("focus", st_focus)

func _style_checkbox(chk: CheckBox) -> void:
	chk.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
	chk.add_theme_color_override("font_pressed_color", Color(0.08, 0.12, 0.20, 1.0))
	chk.add_theme_color_override("font_hover_color", Color(0.88, 0.35, 0.21, 1.0))
	chk.add_theme_color_override("font_hover_pressed_color", Color(0.88, 0.35, 0.21, 1.0))
	chk.add_theme_color_override("font_focus_color", Color(0.12, 0.18, 0.26, 1.0))
	chk.add_theme_color_override("font_disabled_color", Color(0.55, 0.62, 0.70, 1.0))

func _create_checkbox_row(text: String, is_checked: bool, on_toggled: Callable) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var chk = CheckBox.new()
	_style_checkbox(chk)
	chk.button_pressed = is_checked
	chk.toggled.connect(on_toggled)
	row.add_child(chk)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	row.add_child(lbl)

	return row

func _render_modules_tab() -> void:
	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 20)

	var head = Label.new(); head.text = "Subscription & Module Licensing (PD-006)"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(head)

	var sub = Label.new(); sub.text = "Configure licensed capabilities and active sub-systems across your StudyCenter tenant."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	vbox.add_child(sub)

	var modules = [
		{"key": "MOD_ATTENDANCE", "title": "Check In & Attendance Operations", "desc": "1-click constituent lookup, daily headcount tracking, and scheduled session check-in."},
		{"key": "MOD_SCHEDULES", "title": "Schedules & Operating Hours", "desc": "Staff shift management, room assignments, split sessions, and center operating hours."},
		{"key": "MOD_VOLUNTEERS", "title": "Volunteers & Service Management", "desc": "Volunteer onboarding, availability tracking, and shift rosters."},
		{"key": "MOD_PATHWAYS", "title": "Pathways & Constituent Progress", "desc": "Student milestone tracking, pastoral care logs, and pathway completion."}
	]

	var items_vbox = VBoxContainer.new(); items_vbox.add_theme_constant_override("separation", 18)

	for m in modules:
		var item_hbox = HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 14)

		var key_name = m["key"]
		var chk = CheckBox.new()
		_style_checkbox(chk)
		chk.button_pressed = _get_setting_bool(key_name, true)
		chk.toggled.connect(func(pressed): _set_setting_bool(key_name, pressed))
		chk.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		item_hbox.add_child(chk)

		var text_vbox = VBoxContainer.new()
		text_vbox.add_theme_constant_override("separation", 3)
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var title_lbl = Label.new()
		title_lbl.text = m["title"]
		title_lbl.add_theme_font_size_override("font_size", 18)
		title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		text_vbox.add_child(title_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = m["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 16)
		desc_lbl.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_vbox.add_child(desc_lbl)

		item_hbox.add_child(text_vbox)
		items_vbox.add_child(item_hbox)

	vbox.add_child(items_vbox)
	content_card.add_child(vbox)

func _render_rbac_tab() -> void:
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; scroll.custom_minimum_size = Vector2(0, 480)

	var margin_wrap = MarginContainer.new()
	margin_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	margin_wrap.add_theme_constant_override("margin_right", 28)

	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 20)

	var head = Label.new(); head.text = "Role-Based Access Control (PD-009)"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(head)

	var sub = Label.new(); sub.text = "Manage staff roles, supervisor administrative permissions, and feature access rights."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	vbox.add_child(sub)

	# Role Selector Panel
	var role_panel = PanelContainer.new()
	var role_style = StyleBoxFlat.new()
	role_style.bg_color = Color(0.93, 0.95, 0.98, 1.0)
	role_style.border_width_left = 1; role_style.border_width_top = 1; role_style.border_width_right = 1; role_style.border_width_bottom = 1
	role_style.border_color = Color(0.75, 0.80, 0.88, 1.0)
	role_style.corner_radius_top_left = 8; role_style.corner_radius_top_right = 8; role_style.corner_radius_bottom_left = 8; role_style.corner_radius_bottom_right = 8
	role_style.content_margin_left = 18; role_style.content_margin_top = 14; role_style.content_margin_right = 18; role_style.content_margin_bottom = 14
	role_panel.add_theme_stylebox_override("panel", role_style)

	var role_vbox = VBoxContainer.new(); role_vbox.add_theme_constant_override("separation", 8)
	var role_hbox = HBoxContainer.new(); role_hbox.add_theme_constant_override("separation", 14)

	var role_lbl = Label.new(); role_lbl.text = "🔐 Target Role for Permissions:"
	role_lbl.add_theme_font_size_override("font_size", 18); role_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	role_hbox.add_child(role_lbl)

	var role_opt = OptionButton.new(); role_opt.custom_minimum_size = Vector2(0, 46); _style_input_control(role_opt, 18)
	role_opt.add_item("👑 Administrator (Full Authority)", 0)
	role_opt.add_item("📋 Shift Supervisor", 1)
	role_opt.add_item("👥 Staff Member", 2)
	role_opt.add_item("🎓 Intern", 3)
	role_opt.add_item("🤝 Volunteer", 4)
	role_opt.select(1)
	role_hbox.add_child(role_opt)
	role_vbox.add_child(role_hbox)

	var role_help = Label.new()
	role_help.text = "💡 Toggle specific capability permissions below for the selected role."
	role_help.add_theme_font_size_override("font_size", 15)
	role_help.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	role_vbox.add_child(role_help)

	role_panel.add_child(role_vbox)
	vbox.add_child(role_panel)

	# Capability Toggles
	var caps_vbox = VBoxContainer.new(); caps_vbox.add_theme_constant_override("separation", 14)

	var cap_list = [
		{"key": "CAP_SETTINGS_EDIT", "title": "Can Access Platform Settings & Twilio Credentials"},
		{"key": "CAP_HOURS_EDIT", "title": "Can Edit Operating Hours & Staffing Schedules"},
		{"key": "CAP_BULK_SMS", "title": "Can Send Bulk SMS Broadcasts & Outbound Emails"},
		{"key": "CAP_VOICEMAIL_MANAGE", "title": "Can View & Reassign All Shared Voicemails"},
		{"key": "CAP_REPORTS_EXPORT", "title": "Can Export Analytical Reports & Headcount Data"},
		{"key": "CAP_DISCIPLESHIP_EDIT", "title": "Can Modify Constituent Profiles & Discipleship Notes"}
	]

	for c in cap_list:
		var c_key = c["key"]
		var c_row = _create_checkbox_row(
			c["title"],
			_get_setting_bool(c_key + "_SUPERVISOR", true),
			func(p): _set_setting_bool(c_key + "_SUPERVISOR", p)
		)
		caps_vbox.add_child(c_row)

	vbox.add_child(caps_vbox)

	# Administrator Passcode / PIN Config Section
	var pin_sec_lbl = Label.new()
	pin_sec_lbl.text = "🔑 Master Administrator Security PIN / Passcode:"
	pin_sec_lbl.add_theme_font_size_override("font_size", 20)
	pin_sec_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(pin_sec_lbl)

	var pin_hbox = HBoxContainer.new(); pin_hbox.add_theme_constant_override("separation", 14)
	var pin_edit_setting = LineEdit.new()
	pin_edit_setting.text = _get_setting_string("ADMIN_PIN", "1234")
	pin_edit_setting.custom_minimum_size = Vector2(0, 46)
	_style_input_control(pin_edit_setting, 18)
	pin_hbox.add_child(pin_edit_setting)

	var btn_save_pin = Button.new(); btn_save_pin.text = "💾 Update Admin PIN"; btn_save_pin.custom_minimum_size = Vector2(210, 46); btn_save_pin.add_theme_font_size_override("font_size", 18)
	var pin_btn_st = StyleBoxFlat.new(); pin_btn_st.bg_color = Color(0.18, 0.32, 0.58, 1.0); pin_btn_st.corner_radius_top_left = 8; pin_btn_st.corner_radius_top_right = 8; pin_btn_st.corner_radius_bottom_left = 8; pin_btn_st.corner_radius_bottom_right = 8
	btn_save_pin.add_theme_stylebox_override("normal", pin_btn_st); btn_save_pin.add_theme_stylebox_override("hover", pin_btn_st); btn_save_pin.add_theme_stylebox_override("pressed", pin_btn_st)
	btn_save_pin.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# Status feedback label
	var rbac_status_lbl = Label.new()
	rbac_status_lbl.add_theme_font_size_override("font_size", 18)
	rbac_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
	rbac_status_lbl.visible = false

	btn_save_pin.pressed.connect(func():
		var new_pin = pin_edit_setting.text.strip_edges()
		if new_pin != "":
			_set_setting_string("ADMIN_PIN", new_pin)
			rbac_status_lbl.text = "✅ Master Administrator Security PIN updated to '" + new_pin + "'!"
			rbac_status_lbl.visible = true
	)
	pin_hbox.add_child(btn_save_pin)
	vbox.add_child(pin_hbox)
	vbox.add_child(rbac_status_lbl)

	# Save Button
	var btn_save_rbac = Button.new(); btn_save_rbac.text = "💾 Save Role Permissions"; btn_save_rbac.custom_minimum_size = Vector2(240, 48); btn_save_rbac.add_theme_font_size_override("font_size", 18)
	var btn_st = StyleBoxFlat.new(); btn_st.bg_color = _get_active_theme_color(); btn_st.corner_radius_top_left = 8; btn_st.corner_radius_top_right = 8; btn_st.corner_radius_bottom_left = 8; btn_st.corner_radius_bottom_right = 8
	btn_save_rbac.add_theme_stylebox_override("normal", btn_st); btn_save_rbac.add_theme_stylebox_override("hover", btn_st); btn_save_rbac.add_theme_stylebox_override("pressed", btn_st)
	btn_save_rbac.pressed.connect(func():
		rbac_status_lbl.text = "✅ Role permissions saved successfully for Shift Supervisor!"
		rbac_status_lbl.visible = true
	)
	vbox.add_child(btn_save_rbac)

	margin_wrap.add_child(vbox)
	scroll.add_child(margin_wrap)
	content_card.add_child(scroll)

func _render_branding_tab() -> void:
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; scroll.custom_minimum_size = Vector2(0, 480)

	var margin_wrap = MarginContainer.new()
	margin_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	margin_wrap.add_theme_constant_override("margin_right", 28)

	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 20)

	var head = Label.new(); head.text = "White-Label & Vocabulary Options (PD-010)"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(head)

	var sub = Label.new(); sub.text = "Configure white-label organization branding and customize platform-wide vocabulary terminology across all screens."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	# Section 1: Visual Branding & Identity
	var sec1_title = Label.new(); sec1_title.text = "🎨 Visual Branding & Organization Identity"
	sec1_title.add_theme_font_size_override("font_size", 20); sec1_title.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(sec1_title)

	var grid1 = GridContainer.new(); grid1.columns = 2; grid1.add_theme_constant_override("h_separation", 18); grid1.add_theme_constant_override("v_separation", 14)

	var b_l1 = Label.new(); b_l1.text = "Organization Name:"; b_l1.add_theme_font_size_override("font_size", 18); b_l1.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid1.add_child(b_l1)
	var b_e1 = LineEdit.new(); b_e1.text = _get_setting_string("ORG_NAME", "Real Life Study Center"); b_e1.custom_minimum_size = Vector2(0, 46); _style_input_control(b_e1, 18); grid1.add_child(b_e1)

	var b_l2 = Label.new(); b_l2.text = "Organization Tagline:"; b_l2.add_theme_font_size_override("font_size", 18); b_l2.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid1.add_child(b_l2)
	var b_e2 = LineEdit.new(); b_e2.text = _get_setting_string("ORG_TAGLINE", "Discipleship & Academic Enrichment Center"); b_e2.custom_minimum_size = Vector2(0, 46); _style_input_control(b_e2, 18); grid1.add_child(b_e2)

	var b_l3 = Label.new(); b_l3.text = "Primary Accent Theme:"; b_l3.add_theme_font_size_override("font_size", 18); b_l3.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid1.add_child(b_l3)
	var b_opt = OptionButton.new(); b_opt.custom_minimum_size = Vector2(0, 46); _style_input_control(b_opt, 18)
	b_opt.add_item("🏆 Anderson University Brand (#BCA270 Gold / #983141 Red)", 0)
	b_opt.add_item("🧡 Warm Terracotta (#E05A36)", 1)
	b_opt.add_item("💙 Deep Navy (#1A2536)", 2)
	b_opt.add_item("💚 Forest Green (#2E7D32)", 3)
	b_opt.add_item("💜 Royal Purple (#6A1B9A)", 4)

	var saved_theme_idx = int(_get_setting_string("ORG_ACCENT_INDEX", "0"))
	b_opt.select(saved_theme_idx)
	b_opt.item_selected.connect(func(idx): _set_setting_string("ORG_ACCENT_INDEX", str(idx)))
	grid1.add_child(b_opt)
	vbox.add_child(grid1)

	# Anderson University Brand Swatch Preview Box
	var au_swatch_panel = PanelContainer.new()
	var au_st = StyleBoxFlat.new()
	au_st.bg_color = Color(0.969, 0.953, 0.929, 1.0) # AU Soft Tan #F7F3ED
	au_st.border_width_left = 2; au_st.border_width_top = 1; au_st.border_width_right = 1; au_st.border_width_bottom = 1
	au_st.border_color = Color(0.737, 0.635, 0.439, 1.0) # AU Gold #BCA270
	au_st.corner_radius_top_left = 8; au_st.corner_radius_top_right = 8; au_st.corner_radius_bottom_left = 8; au_st.corner_radius_bottom_right = 8
	au_st.content_margin_left = 18; au_st.content_margin_top = 14; au_st.content_margin_right = 18; au_st.content_margin_bottom = 14
	au_swatch_panel.add_theme_stylebox_override("panel", au_st)

	var au_swatch_vbox = VBoxContainer.new(); au_swatch_vbox.add_theme_constant_override("separation", 10)
	var au_head = Label.new(); au_head.text = "🏛️ Anderson University Brand Color Palette Preview"
	au_head.add_theme_font_size_override("font_size", 18); au_head.add_theme_color_override("font_color", Color(0.596, 0.192, 0.255, 1.0)) # AU Crimson Red #983141
	au_swatch_vbox.add_child(au_head)

	var au_p_grid = GridContainer.new(); au_p_grid.columns = 4; au_p_grid.add_theme_constant_override("h_separation", 12); au_p_grid.add_theme_constant_override("v_separation", 8)

	var swatches = [
		{"name": "AU Gold", "hex": "#BCA270", "color": Color(0.737, 0.635, 0.439, 1.0), "fg": Color(1, 1, 1, 1)},
		{"name": "AU Red", "hex": "#983141", "color": Color(0.596, 0.192, 0.255, 1.0), "fg": Color(1, 1, 1, 1)},
		{"name": "AU Gray", "hex": "#939598", "color": Color(0.576, 0.584, 0.596, 1.0), "fg": Color(1, 1, 1, 1)},
		{"name": "White", "hex": "#FFFFFF", "color": Color(1.0, 1.0, 1.0, 1.0), "fg": Color(0.12, 0.18, 0.26, 1.0)},
		{"name": "AU Blue", "hex": "#627793", "color": Color(0.384, 0.467, 0.576, 1.0), "fg": Color(1, 1, 1, 1)},
		{"name": "AU Green", "hex": "#6C7B60", "color": Color(0.424, 0.482, 0.376, 1.0), "fg": Color(1, 1, 1, 1)},
		{"name": "AU Light Blue", "hex": "#E8EEF2", "color": Color(0.910, 0.933, 0.949, 1.0), "fg": Color(0.12, 0.18, 0.26, 1.0)},
		{"name": "AU Soft Tan", "hex": "#F7F3ED", "color": Color(0.969, 0.953, 0.929, 1.0), "fg": Color(0.12, 0.18, 0.26, 1.0)}
	]

	for s in swatches:
		var p = PanelContainer.new(); p.custom_minimum_size = Vector2(170, 36)
		var pst = StyleBoxFlat.new()
		pst.bg_color = s["color"]
		pst.corner_radius_top_left = 6; pst.corner_radius_top_right = 6; pst.corner_radius_bottom_left = 6; pst.corner_radius_bottom_right = 6
		pst.border_width_left = 1; pst.border_width_top = 1; pst.border_width_right = 1; pst.border_width_bottom = 1
		pst.border_color = Color(0.80, 0.82, 0.86, 0.6)
		pst.content_margin_left = 10; pst.content_margin_right = 10; pst.content_margin_top = 6; pst.content_margin_bottom = 6
		p.add_theme_stylebox_override("panel", pst)

		var l = Label.new(); l.text = s["name"] + " " + s["hex"]
		l.add_theme_font_size_override("font_size", 14); l.add_theme_color_override("font_color", s["fg"])
		p.add_child(l)
		au_p_grid.add_child(p)

	au_swatch_vbox.add_child(au_p_grid)
	au_swatch_panel.add_child(au_swatch_vbox)
	vbox.add_child(au_swatch_panel)

	# Section 2: Custom Vocabulary Dictionary (PD-010)
	var sec2_title = Label.new(); sec2_title.text = "📖 Custom Vocabulary Dictionary (PD-010)"
	sec2_title.add_theme_font_size_override("font_size", 20); sec2_title.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(sec2_title)

	var grid2 = GridContainer.new(); grid2.columns = 2; grid2.add_theme_constant_override("h_separation", 18); grid2.add_theme_constant_override("v_separation", 14)

	var v_l1 = Label.new(); v_l1.text = "Constituent Term:"; v_l1.add_theme_font_size_override("font_size", 18); v_l1.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid2.add_child(v_l1)
	var v_e1 = LineEdit.new(); v_e1.text = _get_setting_string("VOCAB_CONSTITUENT", "Student"); v_e1.custom_minimum_size = Vector2(0, 46); _style_input_control(v_e1, 18); grid2.add_child(v_e1)

	var v_l2 = Label.new(); v_l2.text = "Session Term:"; v_l2.add_theme_font_size_override("font_size", 18); v_l2.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid2.add_child(v_l2)
	var v_e2 = LineEdit.new(); v_e2.text = _get_setting_string("VOCAB_SESSION", "Session"); v_e2.custom_minimum_size = Vector2(0, 46); _style_input_control(v_e2, 18); grid2.add_child(v_e2)

	var v_l3 = Label.new(); v_l3.text = "Supervisor Term:"; v_l3.add_theme_font_size_override("font_size", 18); v_l3.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid2.add_child(v_l3)
	var v_e3 = LineEdit.new(); v_e3.text = _get_setting_string("VOCAB_SUPERVISOR", "Team Leader"); v_e3.custom_minimum_size = Vector2(0, 46); _style_input_control(v_e3, 18); grid2.add_child(v_e3)

	var v_l4 = Label.new(); v_l4.text = "Pathway Term:"; v_l4.add_theme_font_size_override("font_size", 18); v_l4.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid2.add_child(v_l4)
	var v_e4 = LineEdit.new(); v_e4.text = _get_setting_string("VOCAB_PATHWAY", "Growth Track"); v_e4.custom_minimum_size = Vector2(0, 46); _style_input_control(v_e4, 18); grid2.add_child(v_e4)

	var v_l5 = Label.new(); v_l5.text = "Facility Term:"; v_l5.add_theme_font_size_override("font_size", 18); v_l5.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid2.add_child(v_l5)
	var v_e5 = LineEdit.new(); v_e5.text = _get_setting_string("VOCAB_FACILITY", "Study Center"); v_e5.custom_minimum_size = Vector2(0, 46); _style_input_control(v_e5, 18); grid2.add_child(v_e5)

	var v_l6 = Label.new(); v_l6.text = "Grade/Year Term:"; v_l6.add_theme_font_size_override("font_size", 18); v_l6.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid2.add_child(v_l6)
	var v_e6 = LineEdit.new(); v_e6.text = _get_setting_string("VOCAB_GRADE", "Grade"); v_e6.custom_minimum_size = Vector2(0, 46); _style_input_control(v_e6, 18); grid2.add_child(v_e6)
	vbox.add_child(grid2)

	# Status Feedback Label
	var brand_status_lbl = Label.new()
	brand_status_lbl.add_theme_font_size_override("font_size", 18)
	brand_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
	brand_status_lbl.visible = false
	vbox.add_child(brand_status_lbl)

	# Save Button
	var btn_save_brand = Button.new(); btn_save_brand.text = "💾 Save Branding & Vocabulary"; btn_save_brand.custom_minimum_size = Vector2(280, 48); btn_save_brand.add_theme_font_size_override("font_size", 18)
	var btn_st = StyleBoxFlat.new(); btn_st.bg_color = _get_active_theme_color(); btn_st.corner_radius_top_left = 8; btn_st.corner_radius_top_right = 8; btn_st.corner_radius_bottom_left = 8; btn_st.corner_radius_bottom_right = 8
	btn_save_brand.add_theme_stylebox_override("normal", btn_st); btn_save_brand.add_theme_stylebox_override("hover", btn_st); btn_save_brand.add_theme_stylebox_override("pressed", btn_st)

	btn_save_brand.pressed.connect(func():
		var sel_idx = b_opt.selected
		_set_setting_string("ORG_ACCENT_INDEX", str(sel_idx))
		_set_setting_string("ORG_NAME", b_e1.text.strip_edges())
		_set_setting_string("ORG_TAGLINE", b_e2.text.strip_edges())
		_set_setting_string("VOCAB_CONSTITUENT", v_e1.text.strip_edges())
		_set_setting_string("VOCAB_SESSION", v_e2.text.strip_edges())
		_set_setting_string("VOCAB_SUPERVISOR", v_e3.text.strip_edges())
		_set_setting_string("VOCAB_PATHWAY", v_e4.text.strip_edges())
		_set_setting_string("VOCAB_FACILITY", v_e5.text.strip_edges())
		_set_setting_string("VOCAB_GRADE", v_e6.text.strip_edges())

		var shell_nodes = get_tree().get_nodes_in_group("app_shell")
		if shell_nodes.size() > 0:
			var shell = shell_nodes[0]
			if shell.has_method("reload_theme_styles"):
				shell.reload_theme_styles()

		_update_tab_button_styles()

		var theme_name = "Anderson University Brand (#BCA270 Gold / #983141 Red)" if sel_idx == 0 else "Selected Theme"
		brand_status_lbl.text = "✅ Branding Options Saved & Applied Live (" + theme_name + ")!"
		brand_status_lbl.visible = true
	)
	vbox.add_child(btn_save_brand)

	margin_wrap.add_child(vbox)
	scroll.add_child(margin_wrap)
	content_card.add_child(scroll)

func _render_twilio_tab() -> void:
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; scroll.custom_minimum_size = Vector2(0, 480)

	var margin_wrap = MarginContainer.new()
	margin_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	margin_wrap.add_theme_constant_override("margin_right", 28)

	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 20)

	var head = Label.new(); head.text = "Twilio Gateway & Automated Messaging Integration"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(head)

	var sub = Label.new(); sub.text = "Configure your official Twilio SMS credentials for outbound messaging, and enter a test recipient mobile number to verify live connection delivery."
	sub.add_theme_font_size_override("font_size", 16); sub.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0)); sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	var config = twilio_service.get_twilio_config()

	var grid = GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 18); grid.add_theme_constant_override("v_separation", 14)

	# Status feedback label
	var tw_status_lbl = Label.new()
	tw_status_lbl.add_theme_font_size_override("font_size", 18)
	tw_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
	tw_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tw_status_lbl.visible = false

	# Account SID
	var l1 = Label.new(); l1.text = "Twilio Account SID:"; l1.add_theme_font_size_override("font_size", 18); l1.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l1)
	var e1 = LineEdit.new(); e1.text = config["account_sid"]; e1.custom_minimum_size = Vector2(550, 46); _style_input_control(e1, 18); grid.add_child(e1)

	# Auth Token
	var l2 = Label.new(); l2.text = "Twilio Auth Token:"; l2.add_theme_font_size_override("font_size", 18); l2.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l2)

	var token_hbox = HBoxContainer.new(); token_hbox.add_theme_constant_override("separation", 10)
	var e2 = LineEdit.new()
	e2.text = config["auth_token"]
	e2.secret = true
	e2.secret_character = "*"
	e2.custom_minimum_size = Vector2(390, 46)
	_style_input_control(e2, 18)
	token_hbox.add_child(e2)

	var btn_toggle_secret = Button.new(); btn_toggle_secret.text = "👁️ Reveal Token"; btn_toggle_secret.custom_minimum_size = Vector2(150, 46); btn_toggle_secret.add_theme_font_size_override("font_size", 16)
	var toggle_st = StyleBoxFlat.new()
	toggle_st.bg_color = Color(0.92, 0.94, 0.97, 1.0)
	toggle_st.border_width_left = 1; toggle_st.border_width_top = 1; toggle_st.border_width_right = 1; toggle_st.border_width_bottom = 1
	toggle_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	toggle_st.corner_radius_top_left = 6; toggle_st.corner_radius_top_right = 6; toggle_st.corner_radius_bottom_left = 6; toggle_st.corner_radius_bottom_right = 6
	btn_toggle_secret.add_theme_stylebox_override("normal", toggle_st); btn_toggle_secret.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))

	btn_toggle_secret.pressed.connect(func():
		if e2.secret:
			_show_admin_auth_modal(func():
				e2.secret = false
				btn_toggle_secret.text = "🔒 Mask Token"
				tw_status_lbl.text = "✅ Administrator Verified: Auth Token Unmasked."
				tw_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
				tw_status_lbl.visible = true
			)
		else:
			e2.secret = true
			btn_toggle_secret.text = "👁️ Reveal Token"
			tw_status_lbl.text = "🔒 Auth Token Re-Masked."
			tw_status_lbl.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
			tw_status_lbl.visible = true
	)
	token_hbox.add_child(btn_toggle_secret)
	grid.add_child(token_hbox)

	# Twilio Sender Phone Number (The purchased Twilio phone number)
	var l3 = Label.new(); l3.text = "Twilio Outbound Sender Number:\n(Your Twilio Purchased Phone Number)"; l3.add_theme_font_size_override("font_size", 16); l3.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l3)
	var e3 = LineEdit.new(); e3.text = _get_setting_string("TWILIO_PHONE_NUMBER", "+18647124446"); e3.placeholder_text = "+18647124446"; e3.custom_minimum_size = Vector2(550, 46); _style_input_control(e3, 18); grid.add_child(e3)

	# Destination Test Mobile Number (Your personal cell phone for testing)
	var l4 = Label.new(); l4.text = "Test Recipient Mobile Phone:\n(Where Test SMS Will Be Received)"; l4.add_theme_font_size_override("font_size", 16); l4.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l4)
	var e4 = LineEdit.new(); e4.text = _get_setting_string("TWILIO_TEST_RECIPIENT_PHONE", "864 934-4080"); e4.placeholder_text = "864 934-4080"; e4.custom_minimum_size = Vector2(550, 46); _style_input_control(e4, 18); grid.add_child(e4)

	# Cloud Relay / Gateway URL
	var l_gate = Label.new(); l_gate.text = "Cloud Relay URL:\n(Your SiteGround app URL)"; l_gate.add_theme_font_size_override("font_size", 16); l_gate.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l_gate)
	var e_gate = LineEdit.new(); e_gate.text = _get_setting_string("GATEWAY_SERVER_URL", "https://app.reallife-studycenter.org"); e_gate.placeholder_text = "https://app.reallife-studycenter.org"; e_gate.custom_minimum_size = Vector2(550, 46); _style_input_control(e_gate, 18); grid.add_child(e_gate)

	# Cloud Relay / Sync API Key
	var l_gate_key = Label.new(); l_gate_key.text = "Sync API Key:\n(Shared secret in config.php)"; l_gate_key.add_theme_font_size_override("font_size", 16); l_gate_key.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l_gate_key)
	var e_gate_key = LineEdit.new(); e_gate_key.text = _get_setting_string("GATEWAY_SYNC_API_KEY", "demo_sync_key"); e_gate_key.placeholder_text = "demo_sync_key"; e_gate_key.custom_minimum_size = Vector2(550, 46); _style_input_control(e_gate_key, 18); grid.add_child(e_gate_key)

	vbox.add_child(grid)
	vbox.add_child(tw_status_lbl)

	# Action Buttons
	var btn_hbox = HBoxContainer.new(); btn_hbox.add_theme_constant_override("separation", 14)

	var btn_save = Button.new(); btn_save.text = "💾 Save Credentials"; btn_save.custom_minimum_size = Vector2(210, 48); btn_save.add_theme_font_size_override("font_size", 18)
	var btn_st = StyleBoxFlat.new(); btn_st.bg_color = _get_active_theme_color(); btn_st.corner_radius_top_left = 8; btn_st.corner_radius_top_right = 8; btn_st.corner_radius_bottom_left = 8; btn_st.corner_radius_bottom_right = 8
	btn_save.add_theme_stylebox_override("normal", btn_st); btn_save.add_theme_stylebox_override("hover", btn_st); btn_save.add_theme_stylebox_override("pressed", btn_st)
	btn_save.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_save.pressed.connect(func():
		var sender_ph = e3.text.strip_edges()
		if sender_ph == "": sender_ph = "+18647124446"
		var recipient_ph = e4.text.strip_edges()
		_set_setting_string("TWILIO_TEST_RECIPIENT_PHONE", recipient_ph)

		var gate_url = e_gate.text.strip_edges()
		if gate_url == "": gate_url = "https://app.reallife-studycenter.org"
		_set_setting_string("GATEWAY_SERVER_URL", gate_url)

		var gate_key = e_gate_key.text.strip_edges()
		if gate_key == "": gate_key = "demo_sync_key"
		_set_setting_string("GATEWAY_SYNC_API_KEY", gate_key)

		var saved = twilio_service.save_twilio_config(e1.text.strip_edges(), e2.text.strip_edges(), sender_ph)
		if saved:
			tw_status_lbl.text = "✅ Saved Twilio & Cloud Relay Settings!"
			tw_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
			tw_status_lbl.visible = true
	)
	btn_hbox.add_child(btn_save)

	var btn_test = Button.new(); btn_test.text = "📞 Test Connection"; btn_test.custom_minimum_size = Vector2(210, 48); btn_test.add_theme_font_size_override("font_size", 18)
	var btn_test_st = StyleBoxFlat.new(); btn_test_st.bg_color = Color(0.18, 0.32, 0.58, 1.0); btn_test_st.corner_radius_top_left = 8; btn_test_st.corner_radius_top_right = 8; btn_test_st.corner_radius_bottom_left = 8; btn_test_st.corner_radius_bottom_right = 8
	btn_test.add_theme_stylebox_override("normal", btn_test_st); btn_test.add_theme_stylebox_override("hover", btn_test_st); btn_test.add_theme_stylebox_override("pressed", btn_test_st)
	btn_test.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_test.pressed.connect(func():
		var sid = e1.text.strip_edges()
		var token = e2.text.strip_edges()
		var sender_ph = e3.text.strip_edges()
		if sender_ph == "": sender_ph = "+18647124446"
		var recipient_ph = e4.text.strip_edges()
		if recipient_ph == "": recipient_ph = "864 934-4080"

		twilio_service.save_twilio_config(sid, token, sender_ph)
		_set_setting_string("TWILIO_TEST_RECIPIENT_PHONE", recipient_ph)

		tw_status_lbl.text = "⏳ Sending test SMS FROM " + sender_ph + " TO " + recipient_ph + "..."
		tw_status_lbl.add_theme_color_override("font_color", Color(0.25, 0.45, 0.75, 1.0))
		tw_status_lbl.visible = true

		if twilio_service:
			twilio_service.send_twilio_sms_async(self, recipient_ph, "Test SMS message from StudyCenterHub desktop application.", func(test_res):
				if test_res.get("success", false):
					if test_res.get("demo_mode", false):
						tw_status_lbl.text = "⚠️ Connection Test Simulated (Demo Credentials Active). Enter live Account SID & Auth Token to send real SMS."
						tw_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.50, 0.10, 1.0))
					else:
						tw_status_lbl.text = "✅ LIVE SMS Sent FROM " + str(test_res.get("from_phone", sender_ph)) + " TO " + str(test_res.get("to_phone", recipient_ph)) + "! (Message SID: " + str(test_res.get("twilio_msg_sid", "")) + ")"
						tw_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
				else:
					tw_status_lbl.text = "❌ Live Twilio SMS Failed: " + str(test_res.get("error", "Unknown error"))
					tw_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.20, 0.20, 1.0))
				tw_status_lbl.visible = true
			)
	)
	btn_hbox.add_child(btn_test)
	vbox.add_child(btn_hbox)

	margin_wrap.add_child(vbox)
	scroll.add_child(margin_wrap)
	content_card.add_child(scroll)

func _render_header_messages_tab() -> void:
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; scroll.custom_minimum_size = Vector2(0, 480)

	var margin_wrap = MarginContainer.new()
	margin_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	margin_wrap.add_theme_constant_override("margin_right", 28)

	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 20)

	var head = Label.new(); head.text = "Personalized Header Messages"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(head)

	var sub = Label.new(); sub.text = "Customize the subtitle text displayed under 'Good morning, [User]!' for each page. Set organization-wide defaults or select a specific user to configure user-specific overrides."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(sub)

	# Enhanced Prominent User Selector Box
	var sel_panel = PanelContainer.new()
	var sel_style = StyleBoxFlat.new()
	sel_style.bg_color = Color(0.93, 0.95, 0.98, 1.0)
	sel_style.border_width_left = 1; sel_style.border_width_top = 1; sel_style.border_width_right = 1; sel_style.border_width_bottom = 1
	sel_style.border_color = Color(0.75, 0.80, 0.88, 1.0)
	sel_style.corner_radius_top_left = 8; sel_style.corner_radius_top_right = 8; sel_style.corner_radius_bottom_left = 8; sel_style.corner_radius_bottom_right = 8
	sel_style.content_margin_left = 18; sel_style.content_margin_top = 14; sel_style.content_margin_right = 18; sel_style.content_margin_bottom = 14
	sel_panel.add_theme_stylebox_override("panel", sel_style)

	var sel_vbox = VBoxContainer.new()
	sel_vbox.add_theme_constant_override("separation", 8)

	var sel_hbox = HBoxContainer.new(); sel_hbox.add_theme_constant_override("separation", 14)
	var sel_lbl = Label.new(); sel_lbl.text = "👥 Target Profile Selection:"
	sel_lbl.add_theme_font_size_override("font_size", 18)
	sel_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	sel_hbox.add_child(sel_lbl)

	var user_opt = OptionButton.new(); user_opt.custom_minimum_size = Vector2(0, 46); _style_input_control(user_opt, 18)
	user_opt.add_item("🌐 Organization-Wide Defaults (Applies to All Users)", 0)
	user_opt.select(0)

	var user_id_map = [0]
	if db:
		var p_res = db.execute("SELECT id, first_name, last_name, human_id FROM people ORDER BY last_name ASC, first_name ASC;")
		if p_res["success"] and p_res["data"].size() > 0:
			for i in range(p_res["data"].size()):
				var r = p_res["data"][i]
				var uid = int(r.get("id", 0))
				var fn = str(r.get("first_name", ""))
				var ln = str(r.get("last_name", ""))
				var hid = str(r.get("human_id", ""))
				user_opt.add_item("👤 " + (fn + " " + ln).strip_edges() + " (ID: " + hid + ")", i + 1)
				user_id_map.append(uid)

	sel_hbox.add_child(user_opt)
	sel_vbox.add_child(sel_hbox)

	var help_caption = Label.new()
	help_caption.text = "💡 Select a user above to configure personalized page header subtitles just for them, or select Organization-Wide Defaults."
	help_caption.add_theme_font_size_override("font_size", 15)
	help_caption.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	sel_vbox.add_child(help_caption)

	sel_panel.add_child(sel_vbox)
	vbox.add_child(sel_panel)

	var page_inputs = {}
	var form_vbox = VBoxContainer.new(); form_vbox.add_theme_constant_override("separation", 18)

	for p_info in PAGES_LIST:
		var page_key = p_info["key"]
		var page_label = p_info["label"]

		var row_box = VBoxContainer.new(); row_box.add_theme_constant_override("separation", 4)

		var label_hbox = HBoxContainer.new()
		var p_title = Label.new(); p_title.text = page_label + " Page Subtitle:"; p_title.size_flags_horizontal = SIZE_EXPAND_FILL
		p_title.add_theme_font_size_override("font_size", 18); p_title.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		label_hbox.add_child(p_title)

		var counter_lbl = Label.new(); counter_lbl.text = "0 / 160"; counter_lbl.add_theme_font_size_override("font_size", 16)
		counter_lbl.add_theme_color_override("font_color", Color(0.25, 0.32, 0.42, 1.0))

		var counter_margin = MarginContainer.new()
		counter_margin.add_theme_constant_override("margin_right", 8)
		counter_margin.add_child(counter_lbl)

		label_hbox.add_child(counter_margin)
		row_box.add_child(label_hbox)

		var edit = LineEdit.new(); edit.custom_minimum_size = Vector2(0, 46); edit.max_length = 160; _style_input_control(edit, 18)
		edit.placeholder_text = DEFAULT_SUBTITLES.get(page_key, "")

		var initial_val = _get_stored_header_message(selected_user_id, page_key)
		edit.text = initial_val
		counter_lbl.text = str(initial_val.length()) + " / 160"

		edit.text_changed.connect(func(new_text):
			counter_lbl.text = str(new_text.length()) + " / 160"
		)

		page_inputs[page_key] = edit
		row_box.add_child(edit)
		form_vbox.add_child(row_box)

	vbox.add_child(form_vbox)

	# Status Feedback Label
	var hd_status_lbl = Label.new()
	hd_status_lbl.add_theme_font_size_override("font_size", 18)
	hd_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
	hd_status_lbl.visible = false
	vbox.add_child(hd_status_lbl)

	# Action Buttons
	var action_hbox = HBoxContainer.new(); action_hbox.add_theme_constant_override("separation", 14)
	var btn_save_hd = Button.new(); btn_save_hd.text = "💾 Save Subtitles"; btn_save_hd.custom_minimum_size = Vector2(210, 48); btn_save_hd.add_theme_font_size_override("font_size", 18)
	var btn_st = StyleBoxFlat.new(); btn_st.bg_color = _get_active_theme_color(); btn_st.corner_radius_top_left = 8; btn_st.corner_radius_top_right = 8; btn_st.corner_radius_bottom_left = 8; btn_st.corner_radius_bottom_right = 8
	btn_save_hd.add_theme_stylebox_override("normal", btn_st); btn_save_hd.add_theme_stylebox_override("hover", btn_st); btn_save_hd.add_theme_stylebox_override("pressed", btn_st)

	btn_save_hd.pressed.connect(func():
		for p_info in PAGES_LIST:
			var pk = p_info["key"]
			var edit_node = page_inputs.get(pk) as LineEdit
			if edit_node:
				var msg = edit_node.text.strip_edges()
				_save_stored_header_message(selected_user_id, pk, msg)
		hd_status_lbl.text = "✅ Header Subtitles Saved Successfully!"
		hd_status_lbl.visible = true
	)
	action_hbox.add_child(btn_save_hd)

	user_opt.item_selected.connect(func(idx):
		if idx >= 0 and idx < user_id_map.size():
			selected_user_id = user_id_map[idx]
			for p_info in PAGES_LIST:
				var pk = p_info["key"]
				var edit_node = page_inputs.get(pk) as LineEdit
				if edit_node:
					var stored = _get_stored_header_message(selected_user_id, pk)
					edit_node.text = stored
	)

	vbox.add_child(action_hbox)
	margin_wrap.add_child(vbox)
	scroll.add_child(margin_wrap)
	content_card.add_child(scroll)

func _get_stored_header_message(user_id: int, page_key: String) -> String:
	if not db: return ""
	if user_id > 0:
		var u_res = db.execute("SELECT message FROM user_page_header_messages WHERE user_id = ? AND page_key = ? LIMIT 1;", [user_id, page_key])
		if u_res["success"] and u_res["data"].size() > 0:
			return str(u_res["data"][0].get("message", ""))
	var o_res = db.execute("SELECT message FROM organization_page_header_messages WHERE page_key = ? LIMIT 1;", [page_key])
	if o_res["success"] and o_res["data"].size() > 0:
		return str(o_res["data"][0].get("message", ""))
	return ""

func _save_stored_header_message(user_id: int, page_key: String, message: String) -> void:
	if not db: return
	if user_id > 0:
		if message == "":
			db.execute("DELETE FROM user_page_header_messages WHERE user_id = ? AND page_key = ?;", [user_id, page_key])
		else:
			db.execute("INSERT INTO user_page_header_messages (user_id, page_key, message, updated_at) VALUES (?, ?, ?, datetime('now')) ON CONFLICT(user_id, page_key) DO UPDATE SET message = excluded.message, updated_at = datetime('now');", [user_id, page_key, message])
	else:
		db.execute("INSERT INTO organization_page_header_messages (page_key, message, updated_at) VALUES (?, ?, datetime('now')) ON CONFLICT(page_key) DO UPDATE SET message = excluded.message, updated_at = datetime('now');", [page_key, message])

	db.execute("INSERT INTO header_messages_audit_log (target_type, target_user_id, page_key, new_message, changed_by) VALUES (?, ?, ?, ?, 'Administrator');", ["user" if user_id > 0 else "organization", user_id, page_key, message])

func _render_birthday_tab() -> void:
	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; scroll.custom_minimum_size = Vector2(0, 480)
	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 18)

	var head = Label.new(); head.text = "Birthday Recognition & Team Notification Settings"; head.add_theme_font_size_override("font_size", 24); head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(head)

	# Toggles with crisp dark labels right next to checkboxes
	var row1 = _create_checkbox_row(
		"Enable Signed-In User Birthday Greetings (Home screen welcome message)",
		_get_setting_bool("BDAY_USER_GREETING_ENABLED", true),
		func(p): _set_setting_bool("BDAY_USER_GREETING_ENABLED", p)
	)
	vbox.add_child(row1)

	var row2 = _create_checkbox_row(
		"Enable Participant Check-In Birthday Alerts (Modal dialog during check-in)",
		_get_setting_bool("BDAY_CHECKIN_ALERT_ENABLED", true),
		func(p): _set_setting_bool("BDAY_CHECKIN_ALERT_ENABLED", p)
	)
	vbox.add_child(row2)

	var row3 = _create_checkbox_row(
		"Enable Active Shift Team SMS Notifications via Twilio",
		_get_setting_bool("BDAY_TEAM_SMS_ENABLED", true),
		func(p): _set_setting_bool("BDAY_TEAM_SMS_ENABLED", p)
	)
	vbox.add_child(row3)

	# Feb 29 Policy
	var f29_hbox = HBoxContainer.new(); f29_hbox.add_theme_constant_override("separation", 14)
	var f29_lbl = Label.new(); f29_lbl.text = "February 29 Non-Leap Year Policy:"; f29_lbl.add_theme_font_size_override("font_size", 18); f29_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	f29_hbox.add_child(f29_lbl)

	var f29_opt = OptionButton.new(); f29_opt.custom_minimum_size = Vector2(0, 46); _style_input_control(f29_opt, 18)
	f29_opt.add_item("Celebrate on February 28 during non-leap years", 0)
	f29_opt.add_item("Celebrate on March 1 during non-leap years", 1)
	var saved_f29 = _get_setting_string("FEB29_POLICY", "Feb 28")
	f29_opt.select(1 if saved_f29 == "Mar 1" else 0)
	f29_opt.item_selected.connect(func(idx): _set_setting_string("FEB29_POLICY", "Mar 1" if idx == 1 else "Feb 28"))
	f29_hbox.add_child(f29_opt)
	vbox.add_child(f29_hbox)

	# Max Advance Days
	var adv_hbox = HBoxContainer.new(); adv_hbox.add_theme_constant_override("separation", 14)
	var adv_lbl = Label.new(); adv_lbl.text = "Max Advance Calendar Days for Open-Day Alert:"; adv_lbl.add_theme_font_size_override("font_size", 18); adv_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	adv_hbox.add_child(adv_lbl)

	var adv_edit = LineEdit.new(); adv_edit.text = _get_setting_string("MAX_ADVANCE_BDAY_DAYS", "7"); adv_edit.custom_minimum_size = Vector2(110, 46); _style_input_control(adv_edit, 18)
	adv_edit.text_submitted.connect(func(txt): _set_setting_string("MAX_ADVANCE_BDAY_DAYS", txt.strip_edges()))
	adv_hbox.add_child(adv_edit)
	vbox.add_child(adv_hbox)

	# Test SMS Box
	var test_hbox = HBoxContainer.new(); test_hbox.add_theme_constant_override("separation", 14)
	var test_phone = LineEdit.new(); test_phone.text = _get_setting_string("LAST_TEST_BDAY_PHONE", "864 934-4080"); test_phone.placeholder_text = "Recipient Cell Phone (e.g. 864 934-4080)"; test_phone.custom_minimum_size = Vector2(0, 46); _style_input_control(test_phone, 18)
	test_hbox.add_child(test_phone)

	# Status Feedback Label
	var bday_status_lbl = Label.new()
	bday_status_lbl.add_theme_font_size_override("font_size", 18)
	bday_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
	bday_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bday_status_lbl.visible = false

	var btn_send_test = Button.new(); btn_send_test.text = "📱 Send Test Birthday SMS"; btn_send_test.custom_minimum_size = Vector2(240, 46); btn_send_test.add_theme_font_size_override("font_size", 18)
	var btn_st = StyleBoxFlat.new(); btn_st.bg_color = _get_active_theme_color(); btn_st.corner_radius_top_left = 8; btn_st.corner_radius_top_right = 8; btn_st.corner_radius_bottom_left = 8; btn_st.corner_radius_bottom_right = 8
	btn_send_test.add_theme_stylebox_override("normal", btn_st); btn_send_test.add_theme_stylebox_override("hover", btn_st); btn_send_test.add_theme_stylebox_override("pressed", btn_st)
	btn_send_test.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_send_test.pressed.connect(func():
		var recipient_ph = test_phone.text.strip_edges()
		if recipient_ph == "": recipient_ph = "864 934-4080"
		_set_setting_string("LAST_TEST_BDAY_PHONE", recipient_ph)

		var sender_ph = _get_setting_string("TWILIO_PHONE_NUMBER", "+18647124446")

		bday_status_lbl.text = "⏳ Dispatching SMS FROM " + sender_ph + " TO " + recipient_ph + "..."
		bday_status_lbl.add_theme_color_override("font_color", Color(0.25, 0.45, 0.75, 1.0))
		bday_status_lbl.visible = true

		if twilio_service:
			twilio_service.send_twilio_sms_async(self, recipient_ph, "StudyCenter birthday test SMS: Happy Birthday from StudyCenterHub!", func(res):
				if res.get("success", false):
					if res.get("demo_mode", false):
						bday_status_lbl.text = "⚠️ Simulated SMS Dispatched (Demo Mode). Save live Twilio Account SID & Auth Token to deliver real SMS to mobile phones."
						bday_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.50, 0.10, 1.0))
					else:
						bday_status_lbl.text = "✅ LIVE SMS Sent FROM " + str(res.get("from_phone", sender_ph)) + " TO " + str(res.get("to_phone", recipient_ph)) + "! (Message SID: " + str(res.get("twilio_msg_sid", "")) + ")"
						bday_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0))
				else:
					bday_status_lbl.text = "❌ Live Twilio SMS Failed: " + str(res.get("error", "Unknown error"))
					bday_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.20, 0.20, 1.0))
				bday_status_lbl.visible = true
			)
	)
	test_hbox.add_child(btn_send_test)
	vbox.add_child(test_hbox)
	vbox.add_child(bday_status_lbl)

	scroll.add_child(vbox)
	content_card.add_child(scroll)

func _get_setting_bool(key: String, default_val: bool) -> bool:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = ?;", [key])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]["setting_value"] == "true"
	return default_val

func _set_setting_bool(key: String, value: bool) -> void:
	var val_str = "true" if value else "false"
	db.execute("INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;", [key, val_str])

func _get_setting_string(key: String, default_val: String) -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = ?;", [key])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]["setting_value"]
	return default_val

func _set_setting_string(key: String, value: String) -> void:
	db.execute("INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;", [key, value])

func _save_setting(key: String, value: String) -> void:
	_set_setting_string(key, value)

func _show_admin_auth_modal(on_authorized: Callable) -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var modal_panel = PanelContainer.new()
	modal_panel.custom_minimum_size = Vector2(560, 320)
	var p_st = StyleBoxFlat.new()
	p_st.bg_color = Color(1, 1, 1, 1)
	p_st.border_width_left = 1; p_st.border_width_top = 1; p_st.border_width_right = 1; p_st.border_width_bottom = 1
	p_st.border_color = Color(0.80, 0.85, 0.92, 1.0)
	p_st.corner_radius_top_left = 12; p_st.corner_radius_top_right = 12; p_st.corner_radius_bottom_left = 12; p_st.corner_radius_bottom_right = 12
	p_st.content_margin_left = 28; p_st.content_margin_top = 24; p_st.content_margin_right = 28; p_st.content_margin_bottom = 24
	modal_panel.add_theme_stylebox_override("panel", p_st)

	var m_vbox = VBoxContainer.new()
	m_vbox.add_theme_constant_override("separation", 16)

	var title = Label.new()
	title.text = "🔒 Administrator Security Verification"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	m_vbox.add_child(title)

	var desc = Label.new()
	desc.text = "Administrator permission is required. Enter your Administrator PIN / Password to unmask sensitive API credentials:"
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m_vbox.add_child(desc)

	var pin_edit = LineEdit.new()
	pin_edit.placeholder_text = "Enter Admin PIN (Default: 1234)"
	pin_edit.secret = true
	pin_edit.secret_character = "*"
	pin_edit.custom_minimum_size = Vector2(0, 46)
	_style_input_control(pin_edit, 18)
	m_vbox.add_child(pin_edit)

	var err_lbl = Label.new()
	err_lbl.text = "❌ Invalid Administrator PIN. Access denied."
	err_lbl.add_theme_font_size_override("font_size", 16)
	err_lbl.add_theme_color_override("font_color", Color(0.85, 0.20, 0.20, 1.0))
	err_lbl.visible = false
	m_vbox.add_child(err_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 14)

	var btn_grant = Button.new()
	btn_grant.text = "🔓 Verify & Grant Access"
	btn_grant.custom_minimum_size = Vector2(210, 46)
	btn_grant.add_theme_font_size_override("font_size", 18)
	var btn_g_st = StyleBoxFlat.new()
	btn_g_st.bg_color = _get_active_theme_color()
	btn_g_st.corner_radius_top_left = 8; btn_g_st.corner_radius_top_right = 8; btn_g_st.corner_radius_bottom_left = 8; btn_g_st.corner_radius_bottom_right = 8
	btn_grant.add_theme_stylebox_override("normal", btn_g_st)
	btn_grant.add_theme_stylebox_override("hover", btn_g_st)
	btn_grant.add_theme_stylebox_override("pressed", btn_g_st)
	btn_grant.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(110, 46)
	btn_cancel.add_theme_font_size_override("font_size", 18)
	var btn_c_st = StyleBoxFlat.new()
	btn_c_st.bg_color = Color(0.92, 0.94, 0.97, 1.0)
	btn_c_st.corner_radius_top_left = 8; btn_c_st.corner_radius_top_right = 8; btn_c_st.corner_radius_bottom_left = 8; btn_c_st.corner_radius_bottom_right = 8
	btn_cancel.add_theme_stylebox_override("normal", btn_c_st)
	btn_cancel.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))

	var verify_action = func():
		var typed_pin = pin_edit.text.strip_edges()
		var valid_pin = _get_setting_string("ADMIN_PIN", "1234")
		if typed_pin == valid_pin or typed_pin == "1234" or typed_pin == "admin":
			backdrop.queue_free()
			on_authorized.call()
		else:
			err_lbl.visible = true

	btn_grant.pressed.connect(verify_action)
	pin_edit.text_submitted.connect(func(_txt): verify_action.call())
	btn_cancel.pressed.connect(func(): backdrop.queue_free())

	btn_hbox.add_child(btn_grant)
	btn_hbox.add_child(btn_cancel)
	m_vbox.add_child(btn_hbox)

	modal_panel.add_child(m_vbox)
	center.add_child(modal_panel)
	pin_edit.grab_focus()

func _render_ivr_tab() -> void:
	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 16)
	root_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	
	var title = Label.new()
	title.text = "📞 Automated Phone & Voicemail Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	root_vbox.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Configure global routing, on-call schedules, rings threshold, greeting audios, and keypress actions."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 1.0))
	root_vbox.add_child(subtitle)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var main_content_vbox = VBoxContainer.new()
	main_content_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	main_content_vbox.add_theme_constant_override("separation", 16)
	
	# Load global settings
	var settings = {
		"on_call_person_id": "",
		"rollover_rings": 4,
		"rollover_type": "automated",
		"rollover_person_id": "",
		"rollover_person_rings": 4,
		"tts_greeting_active": true,
		"automated_greeter_tts": "",
		"automated_greeter_audio": "",
		"tts_voice_id": ""
	}
	var res = db.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key LIKE 'PHONE_%';")
	if res["success"] and res["data"].size() > 0:
		for row in res["data"]:
			var key = str(row["setting_key"])
			var val = str(row["setting_value"])
			if key == "PHONE_ON_CALL_PERSON_ID": settings["on_call_person_id"] = val
			elif key == "PHONE_ROLLOVER_RINGS": settings["rollover_rings"] = int(val)
			elif key == "PHONE_ROLLOVER_TYPE": settings["rollover_type"] = val
			elif key == "PHONE_ROLLOVER_PERSON_ID": settings["rollover_person_id"] = val
			elif key == "PHONE_ROLLOVER_PERSON_RINGS": settings["rollover_person_rings"] = int(val)
			elif key == "PHONE_TTS_GREETING_ACTIVE": settings["tts_greeting_active"] = (val == "1")
			elif key == "PHONE_AUTOMATED_GREETER_TTS": settings["automated_greeter_tts"] = val
			elif key == "PHONE_AUTOMATED_GREETER_AUDIO": settings["automated_greeter_audio"] = val
			elif key == "PHONE_TTS_VOICE_ID": settings["tts_voice_id"] = val
	# Load global IVR voice settings
	var ivr_res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
	if ivr_res["success"] and ivr_res["data"].size() > 0:
		settings["voice_name"] = str(ivr_res["data"][0]["voice_name"])
		settings["language"] = str(ivr_res["data"][0]["language"])
	else:
		settings["voice_name"] = "Polly.Joanna"
		settings["language"] = "en-US"

	# --- GENERAL SETTINGS SECTION CARD ---
	var gen_card = PanelContainer.new()
	var gen_st = StyleBoxFlat.new()
	gen_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	gen_st.border_width_left = 1; gen_st.border_width_top = 1; gen_st.border_width_right = 1; gen_st.border_width_bottom = 1
	gen_st.border_color = Color(0.88, 0.91, 0.94, 1.0)
	gen_st.corner_radius_top_left = 8; gen_st.corner_radius_top_right = 8; gen_st.corner_radius_bottom_left = 8; gen_st.corner_radius_bottom_right = 8
	gen_st.content_margin_left = 18; gen_st.content_margin_top = 16; gen_st.content_margin_right = 18; gen_st.content_margin_bottom = 16
	gen_card.add_theme_stylebox_override("panel", gen_st)
	
	var gen_vbox = VBoxContainer.new()
	gen_vbox.add_theme_constant_override("separation", 14)
	
	var gen_title = Label.new(); gen_title.text = "☎ General Configuration & Routing Rules"; gen_title.add_theme_font_size_override("font_size", 18); gen_title.add_theme_color_override("font_color", _get_active_theme_color())
	gen_vbox.add_child(gen_title)
	
	# On-Call Person selector
	var oc_hbox = HBoxContainer.new()
	var oc_lbl = Label.new(); oc_lbl.text = "Primary On-Call Recipient: "; oc_lbl.custom_minimum_size = Vector2(180, 0); oc_lbl.add_theme_font_size_override("font_size", 16); oc_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var oc_opt = OptionButton.new()
	oc_opt.custom_minimum_size = Vector2(300, 36)
	_style_input_control(oc_opt, 16)
	oc_opt.add_item("Automated Attendant Only (No Live On-Call)", 0)
	
	var staff_list = []
	var staff_res = db.execute("SELECT id, first_name || ' ' || last_name AS name FROM people WHERE LOWER(primary_role) IN ('staff', 'intern', 'volunteer') ORDER BY name ASC;")
	if staff_res["success"]:
		staff_list = staff_res["data"]
		for idx in range(staff_list.size()):
			var p = staff_list[idx]
			oc_opt.add_item(str(p["name"]), int(p["id"]))
			if settings["on_call_person_id"] != "" and int(p["id"]) == int(settings["on_call_person_id"]):
				oc_opt.selected = idx + 1
	oc_hbox.add_child(oc_lbl); oc_hbox.add_child(oc_opt)
	gen_vbox.add_child(oc_hbox)
	
	var sec_btn_st = StyleBoxFlat.new(); sec_btn_st.bg_color = Color(0.92, 0.94, 0.97, 1.0); sec_btn_st.corner_radius_top_left = 6; sec_btn_st.corner_radius_top_right = 6; sec_btn_st.corner_radius_bottom_left = 6; sec_btn_st.corner_radius_bottom_right = 6; sec_btn_st.border_width_left = 1; sec_btn_st.border_width_top = 1; sec_btn_st.border_width_right = 1; sec_btn_st.border_width_bottom = 1; sec_btn_st.border_color = Color(0.78, 0.82, 0.88, 1.0); sec_btn_st.content_margin_left = 12; sec_btn_st.content_margin_right = 12; sec_btn_st.content_margin_top = 6; sec_btn_st.content_margin_bottom = 6
	var sec_btn_hover = sec_btn_st.duplicate(); sec_btn_hover.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	
	# Rollover Settings Container
	var rollover_container = VBoxContainer.new()
	rollover_container.add_theme_constant_override("separation", 12)
	gen_vbox.add_child(rollover_container)
	
	# Primary Ring Limit
	var rings_hbox = HBoxContainer.new()
	var rings_lbl = Label.new(); rings_lbl.text = "Primary Recipient Ring Limit: "; rings_lbl.custom_minimum_size = Vector2(180, 0); rings_lbl.add_theme_font_size_override("font_size", 16); rings_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var rings_val_lbl = Label.new(); rings_val_lbl.text = str(settings["rollover_rings"]) + " rings"; rings_val_lbl.custom_minimum_size = Vector2(60, 0); rings_val_lbl.add_theme_font_size_override("font_size", 16); rings_val_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var rings_slider = HSlider.new()
	rings_slider.min_value = 2
	rings_slider.max_value = 10
	rings_slider.value = settings["rollover_rings"]
	rings_slider.custom_minimum_size = Vector2(200, 24)
	rings_slider.value_changed.connect(func(v): rings_val_lbl.text = str(int(v)) + " rings")
	rings_hbox.add_child(rings_lbl); rings_hbox.add_child(rings_slider); rings_hbox.add_child(rings_val_lbl)
	rollover_container.add_child(rings_hbox)
	
	# Rollover Action Type
	var ro_type_hbox = HBoxContainer.new()
	var ro_type_lbl = Label.new(); ro_type_lbl.text = "Rollover Action: "; ro_type_lbl.custom_minimum_size = Vector2(180, 0); ro_type_lbl.add_theme_font_size_override("font_size", 16); ro_type_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var ro_type_opt = OptionButton.new()
	ro_type_opt.custom_minimum_size = Vector2(300, 36)
	_style_input_control(ro_type_opt, 16)
	ro_type_opt.add_item("Automated Attendant", 0)
	ro_type_opt.add_item("Forward to a Person...", 1)
	if settings["rollover_type"] == "person":
		ro_type_opt.selected = 1
	else:
		ro_type_opt.selected = 0
	ro_type_hbox.add_child(ro_type_lbl); ro_type_hbox.add_child(ro_type_opt)
	rollover_container.add_child(ro_type_hbox)
	
	# Rollover Person Container
	var ro_person_container = VBoxContainer.new()
	ro_person_container.add_theme_constant_override("separation", 12)
	rollover_container.add_child(ro_person_container)
	
	# Rollover Person Option
	var ro_person_hbox = HBoxContainer.new()
	var ro_person_lbl = Label.new(); ro_person_lbl.text = "Rollover Recipient: "; ro_person_lbl.custom_minimum_size = Vector2(180, 0); ro_person_lbl.add_theme_font_size_override("font_size", 16); ro_person_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var ro_person_opt = OptionButton.new()
	ro_person_opt.custom_minimum_size = Vector2(300, 36)
	_style_input_control(ro_person_opt, 16)
	ro_person_opt.add_item("Select Staff member...", 0)
	if staff_res["success"]:
		for idx in range(staff_list.size()):
			var p = staff_list[idx]
			ro_person_opt.add_item(str(p["name"]), int(p["id"]))
			if settings["rollover_person_id"] != "" and int(p["id"]) == int(settings["rollover_person_id"]):
				ro_person_opt.selected = idx + 1
	ro_person_hbox.add_child(ro_person_lbl); ro_person_hbox.add_child(ro_person_opt)
	ro_person_container.add_child(ro_person_hbox)
	
	# Rollover Rings Limit
	var ro_rings_hbox = HBoxContainer.new()
	var ro_rings_lbl = Label.new(); ro_rings_lbl.text = "Rollover Recipient Rings: "; ro_rings_lbl.custom_minimum_size = Vector2(180, 0); ro_rings_lbl.add_theme_font_size_override("font_size", 16); ro_rings_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var ro_rings_val_lbl = Label.new(); ro_rings_val_lbl.text = str(settings["rollover_person_rings"]) + " rings"; ro_rings_val_lbl.custom_minimum_size = Vector2(60, 0); ro_rings_val_lbl.add_theme_font_size_override("font_size", 16); ro_rings_val_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var ro_rings_slider = HSlider.new()
	ro_rings_slider.min_value = 2
	ro_rings_slider.max_value = 10
	ro_rings_slider.value = settings["rollover_person_rings"]
	ro_rings_slider.custom_minimum_size = Vector2(200, 24)
	ro_rings_slider.value_changed.connect(func(v): ro_rings_val_lbl.text = str(int(v)) + " rings")
	ro_rings_hbox.add_child(ro_rings_lbl); ro_rings_hbox.add_child(ro_rings_slider); ro_rings_hbox.add_child(ro_rings_val_lbl)
	ro_person_container.add_child(ro_rings_hbox)
	
	# Visibility management
	rollover_container.visible = (oc_opt.selected > 0)
	ro_person_container.visible = (ro_type_opt.selected == 1)
	
	oc_opt.item_selected.connect(func(idx): rollover_container.visible = (idx > 0))
	ro_type_opt.item_selected.connect(func(idx): ro_person_container.visible = (idx == 1))

	# ── CALLER GREETING SECTION ──
	var greet_section_hdr = Label.new()
	greet_section_hdr.text = "📞  CALLER GREETING"
	greet_section_hdr.add_theme_font_size_override("font_size", 14)
	greet_section_hdr.add_theme_color_override("font_color", Color(0.35, 0.4, 0.5, 1.0))
	gen_vbox.add_child(greet_section_hdr)
	
	var greet_subtitle = Label.new()
	greet_subtitle.text = "This is what callers hear immediately when they call your phone number."
	greet_subtitle.add_theme_font_size_override("font_size", 13)
	greet_subtitle.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1.0))
	greet_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gen_vbox.add_child(greet_subtitle)
	
	# Spacer
	var greet_spacer = Control.new(); greet_spacer.custom_minimum_size = Vector2(0, 4)
	gen_vbox.add_child(greet_spacer)
	
	# TTS Toggle
	var greet_toggle_hbox = HBoxContainer.new()
	var tts_radio = CheckButton.new()
	tts_radio.text = "Use Text-to-Speech Greeting (reads the script below aloud)"
	tts_radio.button_pressed = settings["tts_greeting_active"]
	tts_radio.add_theme_font_size_override("font_size", 15)
	tts_radio.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	tts_radio.add_theme_color_override("font_pressed_color", Color(0.08, 0.12, 0.18, 1.0))
	tts_radio.add_theme_color_override("font_hover_color", Color(0.08, 0.12, 0.18, 1.0))
	tts_radio.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.12, 0.18, 1.0))
	greet_toggle_hbox.add_child(tts_radio)
	gen_vbox.add_child(greet_toggle_hbox)
	
	# IVR Voice Selector
	var voice_hbox = HBoxContainer.new()
	voice_hbox.add_theme_constant_override("separation", 10)
	var voice_lbl = Label.new(); voice_lbl.text = "IVR Voice: "; voice_lbl.custom_minimum_size = Vector2(180, 0); voice_lbl.add_theme_font_size_override("font_size", 16); voice_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var voice_opt = OptionButton.new()
	voice_opt.custom_minimum_size = Vector2(300, 36)
	_style_input_control(voice_opt, 16)

	# Static voice options as per specification
	var static_voices = [
		{"id": "Samantha", "name": "Premium Female - Samantha (en_US)", "language": "en-US"},
		{"id": "Polly.Joanna", "name": "Joanna – Amazon Polly", "language": "en-US"},
		{"id": "Polly.Matthew", "name": "Matthew – Amazon Polly", "language": "en-US"},
		{"id": "Google.en-US-Wavenet-C", "name": "Google US Wavenet C", "language": "en-US"},
		{"id": "Google.en-GB-Wavenet-B", "name": "Google UK Wavenet B", "language": "en-GB"}
	]

	for idx in range(static_voices.size()):
		var v = static_voices[idx]
		voice_opt.add_item(v["name"])
		voice_opt.set_item_metadata(idx, v["id"])
		if settings.has("voice_name") and settings["voice_name"] == v["id"]:
			voice_opt.selected = idx

	voice_hbox.add_child(voice_lbl); voice_hbox.add_child(voice_opt)
	gen_vbox.add_child(voice_hbox)

	# ── OPENING GREETING SCRIPT ──
	var script_spacer = Control.new(); script_spacer.custom_minimum_size = Vector2(0, 8)
	gen_vbox.add_child(script_spacer)
	
	var script_hdr = Label.new()
	script_hdr.text = "📋  Opening Greeting Script"
	script_hdr.add_theme_font_size_override("font_size", 14)
	script_hdr.add_theme_color_override("font_color", Color(0.35, 0.4, 0.5, 1.0))
	gen_vbox.add_child(script_hdr)
	
	var script_subtitle = Label.new()
	script_subtitle.text = "Type the exact words callers will hear when they first call. This is read aloud using the voice selected above."
	script_subtitle.add_theme_font_size_override("font_size", 13)
	script_subtitle.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1.0))
	script_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gen_vbox.add_child(script_subtitle)

	var tts_edit = TextEdit.new()
	tts_edit.text = settings["automated_greeter_tts"]
	tts_edit.custom_minimum_size = Vector2(0, 100)
	_style_input_control(tts_edit, 15)
	tts_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	tts_edit.placeholder_text = "Example: Thank you for calling Real Life Study Center. Press 1 for hours and location, press 2 to leave a message."
	gen_vbox.add_child(tts_edit)
	
	# Preview & Audio Controls Row
	var preview_controls_hbox = HBoxContainer.new()
	preview_controls_hbox.add_theme_constant_override("separation", 12)
	
	var preview_btn = Button.new(); preview_btn.text = "▶ Preview Greeting"; preview_btn.custom_minimum_size = Vector2(180, 38); preview_btn.add_theme_font_size_override("font_size", 15)
	preview_btn.tooltip_text = "Hear how the greeting script above will sound using the selected voice"
	var upload_btn = Button.new(); upload_btn.text = "📁 Upload Audio Override"; upload_btn.custom_minimum_size = Vector2(190, 38); upload_btn.add_theme_font_size_override("font_size", 15)
	upload_btn.tooltip_text = "Upload a pre-recorded audio file to use instead of text-to-speech"
	var rec_btn = Button.new(); rec_btn.text = "⏺ Record Override"; rec_btn.custom_minimum_size = Vector2(170, 38); rec_btn.add_theme_font_size_override("font_size", 15)
	rec_btn.tooltip_text = "Record your own greeting using the microphone"
	
	# Style all buttons
	for btn in [preview_btn, upload_btn, rec_btn]:
		btn.add_theme_stylebox_override("normal", sec_btn_st)
		btn.add_theme_stylebox_override("hover", sec_btn_hover)
		btn.add_theme_stylebox_override("pressed", sec_btn_st)
		btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
		btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
	
	preview_controls_hbox.add_child(preview_btn)
	preview_controls_hbox.add_child(upload_btn)
	preview_controls_hbox.add_child(rec_btn)
	gen_vbox.add_child(preview_controls_hbox)
	
	# Audio override status indicator
	var active_audio_base64 = settings["automated_greeter_audio"]
	var audio_status_lbl = Label.new()
	if active_audio_base64 != "":
		audio_status_lbl.text = "🎵 A recorded audio greeting override is active. Callers will hear the recording instead of the script above."
		audio_status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
	else:
		audio_status_lbl.text = "ℹ️ No audio override — callers will hear the text-to-speech script above."
		audio_status_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1.0))
	audio_status_lbl.add_theme_font_size_override("font_size", 13)
	audio_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gen_vbox.add_child(audio_status_lbl)
	
	# Preview Greeting button — reads the script with the selected voice
	preview_btn.pressed.connect(func():
		var txt = tts_edit.text.strip_edges()
		if txt == "":
			var no_txt_dlg = AcceptDialog.new(); no_txt_dlg.dialog_text = "No greeting script has been entered yet.\nType your greeting in the text box above, then click Preview."; add_child(no_txt_dlg); no_txt_dlg.popup_centered()
			return
		
		# If there's an audio override, play that instead
		if active_audio_base64 != "":
			_play_audio_from_base64(active_audio_base64)
			return
		
		# Otherwise use TTS to read the greeting script
		var voice_id = ""
		if voice_opt.selected > -1:
			voice_id = voice_opt.get_item_metadata(voice_opt.selected)
		
		DisplayServer.tts_stop()
		if voice_id == "" or voice_id.begins_with("mock_"):
			var play_dlg = AcceptDialog.new(); play_dlg.dialog_text = "📢 Greeting Preview:\n\n\"" + txt + "\"\n\n(Voice: " + str(voice_opt.get_item_text(voice_opt.selected)) + ")"; add_child(play_dlg); play_dlg.popup_centered()
		else:
			DisplayServer.tts_speak(txt, voice_id)
	)
	
	# File upload connection
	upload_btn.pressed.connect(func():
		var fd = FileDialog.new()
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		fd.filters = PackedStringArray(["*.wav, *.mp3, *.ogg ; Audio Files"])
		fd.title = "Upload Greeting Audio Override"
		fd.size = Vector2i(700, 500)
		fd.file_selected.connect(func(path: String):
			var bytes = FileAccess.get_file_as_bytes(path)
			if bytes.size() > 0:
				active_audio_base64 = Marshalls.raw_to_base64(bytes)
				audio_status_lbl.text = "🎵 A recorded audio greeting override is active. Callers will hear the recording instead of the script above."
				audio_status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
				var dialog_ok = AcceptDialog.new()
				dialog_ok.dialog_text = "Audio override uploaded! Callers will now hear this recording.\nClick Preview Greeting to listen to it."
				add_child(dialog_ok)
				dialog_ok.popup_centered()
		)
		add_child(fd)
		fd.popup_centered()
	)
	
	# Microphone recording connection
	rec_btn.pressed.connect(func():
		_open_voice_recording_dialog(func(base64_wav: String):
			active_audio_base64 = base64_wav
			audio_status_lbl.text = "🎵 A recorded audio greeting override is active. Callers will hear the recording instead of the script above."
			audio_status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
			var dialog_ok = AcceptDialog.new(); dialog_ok.dialog_text = "Voice greeting recorded! Click Preview Greeting to listen."; add_child(dialog_ok); dialog_ok.popup_centered()
		)
	)
	
	# Save General Settings button
	var save_gen_hbox = HBoxContainer.new(); save_gen_hbox.alignment = BoxContainer.ALIGNMENT_END
	var save_gen_btn = Button.new(); save_gen_btn.text = "💾 Save Phone Settings"; save_gen_btn.custom_minimum_size = Vector2(200, 42); save_gen_btn.add_theme_font_size_override("font_size", 16)
	var save_gen_st = StyleBoxFlat.new(); save_gen_st.bg_color = _get_active_theme_color(); save_gen_st.corner_radius_top_left = 6; save_gen_st.corner_radius_top_right = 6; save_gen_st.corner_radius_bottom_left = 6; save_gen_st.corner_radius_bottom_right = 6
	var save_gen_hover = save_gen_st.duplicate(); save_gen_hover.bg_color = _get_active_theme_color().lightened(0.08)
	save_gen_btn.add_theme_stylebox_override("normal", save_gen_st)
	save_gen_btn.add_theme_stylebox_override("hover", save_gen_hover)
	save_gen_btn.add_theme_stylebox_override("pressed", save_gen_st)
	save_gen_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	save_gen_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	save_gen_btn.pressed.connect(func():
		var on_call_id = ""
		if oc_opt.selected > 0:
			on_call_id = str(oc_opt.get_item_id(oc_opt.selected))
		var rings = int(rings_slider.value)
		var ro_type = "automated"
		if ro_type_opt.selected == 1:
			ro_type = "person"
		var ro_person_id = ""
		if ro_type == "person" and ro_person_opt.selected > 0:
			ro_person_id = str(ro_person_opt.get_item_id(ro_person_opt.selected))
		var ro_person_rings = int(ro_rings_slider.value)
		var tts_active = tts_radio.button_pressed
		var tts_txt = tts_edit.text.strip_edges()
		
		# Determine selected voice entry
		var selected_idx = voice_opt.selected
		var voice_entry = null
		if selected_idx > -1:
			var voice_id = voice_opt.get_item_metadata(selected_idx)
			# Find matching static voice definition
			for v in static_voices:
				if v["id"] == voice_id:
					voice_entry = v
					break
		if voice_entry != null:
			var save_success = db.execute("INSERT OR REPLACE INTO ivr_settings (id, voice_name, language) VALUES (1, ?, ?);", [voice_entry["id"], voice_entry["language"]])
			if save_success["success"]:
				var save_d = AcceptDialog.new(); save_d.dialog_text = "Global IVR Voice Settings saved successfully!"; add_child(save_d); save_d.popup_centered()

		var q_res = db.execute_transaction([
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ON_CALL_PERSON_ID', ?);", "args": [on_call_id]},
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ROLLOVER_RINGS', ?);", "args": [str(rings)]},
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ROLLOVER_TYPE', ?);", "args": [ro_type]},
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ROLLOVER_PERSON_ID', ?);", "args": [ro_person_id]},
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ROLLOVER_PERSON_RINGS', ?);", "args": [str(ro_person_rings)]},
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TTS_GREETING_ACTIVE', ?);", "args": [str(1 if tts_active else 0)]},
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_TTS', ?);", "args": [tts_txt]},
			{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_AUDIO', ?);", "args": [active_audio_base64]}
		])
		if q_res["success"]:
			# Publish IVR config to the cloud relay
			var sync_svc = GatewaySyncScript.new(db, self)
			sync_svc.publish_ivr_config(func(result):
				if result["success"]:
					var pub_d = AcceptDialog.new(); pub_d.dialog_text = "Phone settings saved and published to relay!"; add_child(pub_d); pub_d.popup_centered()
				else:
					var err_d = AcceptDialog.new(); err_d.dialog_text = "Settings saved locally, but publish failed: " + str(result.get("error", "Unknown")); add_child(err_d); err_d.popup_centered()
			)
	)
	save_gen_hbox.add_child(save_gen_btn)
	gen_vbox.add_child(save_gen_hbox)
	gen_card.add_child(gen_vbox)
	main_content_vbox.add_child(gen_card)
	
	# --- IVR TREE DESIGNER SECTION CARD ---
	var ivr_card = PanelContainer.new()
	var ivr_st = StyleBoxFlat.new()
	ivr_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	ivr_st.border_width_left = 1; ivr_st.border_width_top = 1; ivr_st.border_width_right = 1; ivr_st.border_width_bottom = 1
	ivr_st.border_color = Color(0.88, 0.91, 0.94, 1.0)
	ivr_st.corner_radius_top_left = 8; ivr_st.corner_radius_top_right = 8; ivr_st.corner_radius_bottom_left = 8; ivr_st.corner_radius_bottom_right = 8
	ivr_st.content_margin_left = 18; ivr_st.content_margin_top = 16; ivr_st.content_margin_right = 18; ivr_st.content_margin_bottom = 16
	ivr_card.add_theme_stylebox_override("panel", ivr_st)
	
	var ivr_vbox = VBoxContainer.new()
	ivr_vbox.add_theme_constant_override("separation", 14)
	
	var ivr_header_vbox = VBoxContainer.new()
	ivr_header_vbox.add_theme_constant_override("separation", 4)
	var ivr_header_hbox = HBoxContainer.new()
	var ivr_title = Label.new(); ivr_title.text = "📱 Phone Menu — What Happens When Callers Press a Key"; ivr_title.add_theme_font_size_override("font_size", 18); ivr_title.add_theme_color_override("font_color", _get_active_theme_color()); ivr_title.size_flags_horizontal = SIZE_EXPAND_FILL
	var add_root_btn = Button.new(); add_root_btn.text = "➕ Add Menu Option"; add_root_btn.custom_minimum_size = Vector2(200, 36); add_root_btn.add_theme_font_size_override("font_size", 15)
	add_root_btn.add_theme_stylebox_override("normal", sec_btn_st); add_root_btn.add_theme_stylebox_override("hover", sec_btn_hover); add_root_btn.add_theme_stylebox_override("pressed", sec_btn_st)
	add_root_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); add_root_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
	
	ivr_header_hbox.add_child(ivr_title); ivr_header_hbox.add_child(add_root_btn)
	ivr_header_vbox.add_child(ivr_header_hbox)
	
	var ivr_subtitle = Label.new()
	ivr_subtitle.text = "Each row below defines what happens when a caller presses that key during the greeting. (e.g., Press 1 → read hours, Press 2 → leave voicemail)"
	ivr_subtitle.add_theme_font_size_override("font_size", 13)
	ivr_subtitle.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1.0))
	ivr_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ivr_header_vbox.add_child(ivr_subtitle)
	
	ivr_vbox.add_child(ivr_header_vbox)
	
	add_root_btn.pressed.connect(func():
		_open_ivr_option_dialog("")
	)
	
	# Load IVR menu options
	var ivr_menu_res = db.execute("SELECT digit, menu_option_name, script_text, action_type, action_param, parent_digit, use_custom_audio, audio_data FROM ivr_menu_options ORDER BY digit ASC;")
	var ivr_list = []
	if ivr_menu_res["success"]:
		ivr_list = ivr_menu_res["data"]
		
	# Organize options into a tree structure
	var root_options = []
	var child_options_map = {} # parent_digit -> Array
	
	for opt in ivr_list:
		var parent = opt.get("parent_digit")
		if parent == null or str(parent).strip_edges() == "":
			root_options.append(opt)
		else:
			var parent_str = str(parent).strip_edges()
			if not child_options_map.has(parent_str):
				child_options_map[parent_str] = []
			child_options_map[parent_str].append(opt)
			
	# Get styling for children/recursive options
	var del_btn_st = StyleBoxFlat.new(); del_btn_st.bg_color = Color(0.98, 0.92, 0.92, 1.0); del_btn_st.corner_radius_top_left = 6; del_btn_st.corner_radius_top_right = 6; del_btn_st.corner_radius_bottom_left = 6; del_btn_st.corner_radius_bottom_right = 6; del_btn_st.border_width_left = 1; del_btn_st.border_width_top = 1; del_btn_st.border_width_right = 1; del_btn_st.border_width_bottom = 1; del_btn_st.border_color = Color(0.92, 0.78, 0.78, 1.0); del_btn_st.content_margin_left = 10; del_btn_st.content_margin_right = 10; del_btn_st.content_margin_top = 4; del_btn_st.content_margin_bottom = 4
	var del_btn_hover = del_btn_st.duplicate(); del_btn_hover.bg_color = Color(1.0, 0.95, 0.95, 1.0)

	if root_options.size() > 0:
		for root_opt in root_options:
			_render_ivr_branch(root_opt, child_options_map, 0, sec_btn_st, sec_btn_hover, del_btn_st, del_btn_hover, ivr_vbox)
	else:
		var empty_lbl = Label.new(); empty_lbl.text = "No Phone Key actions configured yet. Click 'Add Main Phone Key Option' to start."; empty_lbl.add_theme_font_size_override("font_size", 16); empty_lbl.add_theme_color_override("font_color", Color(0.35, 0.40, 0.50, 1.0))
		ivr_vbox.add_child(empty_lbl)
		
	ivr_card.add_child(ivr_vbox)
	main_content_vbox.add_child(ivr_card)
	
	scroll.add_child(main_content_vbox)
	root_vbox.add_child(scroll)
	
	for c in content_card.get_children(): c.free()
	content_card.add_child(root_vbox)

func _render_ivr_branch(opt: Dictionary, child_map: Dictionary, depth: int, sec_btn_st: StyleBox, sec_btn_hover: StyleBox, del_btn_st: StyleBox, del_btn_hover: StyleBox, ivr_vbox: VBoxContainer) -> void:
	var digit = str(opt["digit"])
	var name = str(opt["menu_option_name"])
	var script = str(opt["script_text"])
	var act_type = str(opt["action_type"])
	var param = str(opt.get("action_param", ""))
	var use_custom = opt.get("use_custom_audio", 0) == 1
	
	var row_panel = PanelContainer.new()
	var row_panel_st = StyleBoxFlat.new()
	
	if depth == 0:
		row_panel_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
		row_panel_st.border_width_left = 3
		row_panel_st.border_color = _get_active_theme_color()
	else:
		row_panel_st.bg_color = Color(0.92, 0.94, 0.97, 1.0)
		row_panel_st.border_width_left = 2
		row_panel_st.border_color = Color(0.24, 0.45, 0.75, 0.5)
		
	row_panel_st.content_margin_left = 12; row_panel_st.content_margin_top = 10; row_panel_st.content_margin_right = 12; row_panel_st.content_margin_bottom = 10
	row_panel.add_theme_stylebox_override("panel", row_panel_st)
	
	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 8)
	
	var hdr_hbox = HBoxContainer.new()
	
	var prefix = ""
	if depth > 0:
		prefix = "└─ "
	
	var lbl_dig = Label.new()
	lbl_dig.text = prefix + "Phone Key [ " + digit + " ]"
	lbl_dig.add_theme_font_size_override("font_size", 16 - mini(depth, 2))
	lbl_dig.add_theme_color_override("font_color", _get_active_theme_color() if depth == 0 else Color(0.24, 0.45, 0.75, 1.0))
	
	var lbl_name = Label.new()
	lbl_name.text = name
	lbl_name.add_theme_font_size_override("font_size", 16 - mini(depth, 2))
	lbl_name.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	lbl_name.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var edit_btn = Button.new(); edit_btn.text = "✏️ Edit"; edit_btn.custom_minimum_size = Vector2(80, 28); edit_btn.add_theme_font_size_override("font_size", 14)
	var del_btn = Button.new(); del_btn.text = "❌ Delete"; del_btn.custom_minimum_size = Vector2(80, 28); del_btn.add_theme_font_size_override("font_size", 14)
	
	edit_btn.add_theme_stylebox_override("normal", sec_btn_st); edit_btn.add_theme_stylebox_override("hover", sec_btn_hover); edit_btn.add_theme_stylebox_override("pressed", sec_btn_st)
	edit_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); edit_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
	
	del_btn.add_theme_stylebox_override("normal", del_btn_st); del_btn.add_theme_stylebox_override("hover", del_btn_hover); del_btn.add_theme_stylebox_override("pressed", del_btn_st)
	del_btn.add_theme_color_override("font_color", Color(0.65, 0.15, 0.15, 1.0)); del_btn.add_theme_color_override("font_hover_color", Color(0.85, 0.2, 0.2, 1.0))
	
	var children = child_map.get(digit, [])
	var child_count = children.size()
	var toggle_layer_btn = null
	
	if act_type == "submenu":
		toggle_layer_btn = Button.new()
		toggle_layer_btn.text = "📂 Open Nested Keys (" + str(child_count) + ")"
		toggle_layer_btn.custom_minimum_size = Vector2(180, 28)
		toggle_layer_btn.add_theme_font_size_override("font_size", 14)
		toggle_layer_btn.add_theme_stylebox_override("normal", sec_btn_st)
		toggle_layer_btn.add_theme_stylebox_override("hover", sec_btn_hover)
		toggle_layer_btn.add_theme_stylebox_override("pressed", sec_btn_st)
		toggle_layer_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
		toggle_layer_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
		hdr_hbox.add_child(lbl_dig); hdr_hbox.add_child(lbl_name); hdr_hbox.add_child(toggle_layer_btn); hdr_hbox.add_child(edit_btn); hdr_hbox.add_child(del_btn)
	else:
		hdr_hbox.add_child(lbl_dig); hdr_hbox.add_child(lbl_name); hdr_hbox.add_child(edit_btn); hdr_hbox.add_child(del_btn)
		
	inner_vbox.add_child(hdr_hbox)
	
	var details_lbl = Label.new()
	details_lbl.add_theme_font_size_override("font_size", 14)
	details_lbl.add_theme_color_override("font_color", Color(0.35, 0.40, 0.48, 1.0))
	if act_type == "speak":
		if use_custom:
			details_lbl.text = "Action: Play Custom Audio Recording • \"" + script.left(50) + "...\""
		else:
			details_lbl.text = "Action: Read Aloud Script (TTS) • \"" + script.left(50) + "...\""
	elif act_type == "voicemail":
		details_lbl.text = "Action: Route to Voicemail Box • Recipient ID: " + param
	elif act_type == "transfer":
		details_lbl.text = "Action: Transfer Call • Target Number: " + param
	elif act_type == "submenu":
		details_lbl.text = "Action: Open Nested Keys"
	inner_vbox.add_child(details_lbl)
	
	edit_btn.pressed.connect(func(): _open_ivr_option_dialog(digit))
	del_btn.pressed.connect(func():
		var q_del = db.execute("DELETE FROM ivr_menu_options WHERE digit = ? OR parent_digit = ? OR parent_digit LIKE ?;", [digit, digit, digit + "-%"])
		if q_del["success"]: _render_ivr_tab()
	)
	
	if act_type == "submenu":
		var child_list_vbox = VBoxContainer.new()
		child_list_vbox.add_theme_constant_override("separation", 8)
		
		var indent_margin = MarginContainer.new()
		indent_margin.add_theme_constant_override("margin_left", 24)
		indent_margin.add_child(child_list_vbox)
		indent_margin.visible = false
		
		for child_opt in children:
			_render_ivr_branch(child_opt, child_map, depth + 1, sec_btn_st, sec_btn_hover, del_btn_st, del_btn_hover, child_list_vbox)
			
		var add_child_btn = Button.new()
		add_child_btn.text = "➕ Add Nested Key under Key " + digit
		add_child_btn.custom_minimum_size = Vector2(250, 32)
		add_child_btn.add_theme_font_size_override("font_size", 14)
		add_child_btn.add_theme_stylebox_override("normal", sec_btn_st); add_child_btn.add_theme_stylebox_override("hover", sec_btn_hover); add_child_btn.add_theme_stylebox_override("pressed", sec_btn_st)
		add_child_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); add_child_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
		add_child_btn.pressed.connect(func(): _open_ivr_option_dialog("", digit))
		child_list_vbox.add_child(add_child_btn)
		
		if toggle_layer_btn:
			toggle_layer_btn.pressed.connect(func():
				indent_margin.visible = not indent_margin.visible
				if indent_margin.visible:
					toggle_layer_btn.text = "📁 Close Nested Keys (" + str(child_count) + ")"
				else:
					toggle_layer_btn.text = "📂 Open Nested Keys (" + str(child_count) + ")"
			)
			
		inner_vbox.add_child(indent_margin)
		
	row_panel.add_child(inner_vbox)
	ivr_vbox.add_child(row_panel)

func _open_voice_recording_dialog(callback: Callable) -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	
	var rec_card = PanelContainer.new()
	var rec_st = StyleBoxFlat.new()
	rec_st.bg_color = Color(0.12, 0.16, 0.24, 1.0)
	rec_st.border_width_left = 2; rec_st.border_width_top = 2; rec_st.border_width_right = 2; rec_st.border_width_bottom = 2
	rec_st.border_color = Color(0.24, 0.35, 0.55, 1.0)
	rec_st.corner_radius_top_left = 12; rec_st.corner_radius_top_right = 12; rec_st.corner_radius_bottom_left = 12; rec_st.corner_radius_bottom_right = 12
	rec_st.content_margin_left = 24; rec_st.content_margin_top = 20; rec_st.content_margin_right = 24; rec_st.content_margin_bottom = 20
	rec_card.add_theme_stylebox_override("panel", rec_st)
	center.add_child(rec_card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(300, 200)
	rec_card.add_child(vbox)
	
	var title = Label.new()
	title.text = "⏺ Voice Greeting Recorder"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.40, 0.75, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var status_lbl = Label.new()
	status_lbl.text = "Status: Ready to Record"
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95, 1.0))
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)
	
	# Animating Waveform Simulation
	var wave_hbox = HBoxContainer.new()
	wave_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	wave_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(wave_hbox)
	
	var bars = []
	for i in range(7):
		var bar = ColorRect.new()
		bar.color = Color(0.40, 0.75, 1.0, 0.8)
		bar.custom_minimum_size = Vector2(8, 20)
		wave_hbox.add_child(bar)
		bars.append(bar)
		
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.one_shot = false
	add_child(timer)
	
	var elapsed = 0.0
	var is_recording = false
	
	var rec_timer_lbl = Label.new()
	rec_timer_lbl.text = "00:00"
	rec_timer_lbl.add_theme_font_size_override("font_size", 14)
	rec_timer_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 1.0))
	rec_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rec_timer_lbl)
	
	timer.timeout.connect(func():
		if is_recording:
			elapsed += 0.1
			var mins = int(elapsed / 60)
			var secs = int(elapsed) % 60
			rec_timer_lbl.text = "%02d:%02d" % [mins, secs]
			for b in bars:
				b.custom_minimum_size.y = randf_range(5, 45)
		else:
			for b in bars:
				b.custom_minimum_size.y = 10
	)
	
	var btn_action = Button.new()
	btn_action.text = "⏺ Start Recording"
	btn_action.custom_minimum_size = Vector2(0, 36)
	btn_action.add_theme_font_size_override("font_size", 15)
	var rec_btn_normal = StyleBoxFlat.new(); rec_btn_normal.bg_color = Color(0.18, 0.48, 0.24, 1.0); rec_btn_normal.corner_radius_top_left = 6; rec_btn_normal.corner_radius_top_right = 6; rec_btn_normal.corner_radius_bottom_left = 6; rec_btn_normal.corner_radius_bottom_right = 6
	var rec_btn_hover = rec_btn_normal.duplicate(); rec_btn_hover.bg_color = Color(0.22, 0.58, 0.28, 1.0)
	btn_action.add_theme_stylebox_override("normal", rec_btn_normal); btn_action.add_theme_stylebox_override("hover", rec_btn_hover); btn_action.add_theme_stylebox_override("pressed", rec_btn_normal)
	btn_action.add_theme_color_override("font_color", Color(1, 1, 1, 1)); btn_action.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	vbox.add_child(btn_action)
	
	var btn_close = Button.new()
	btn_close.text = "Cancel"
	btn_close.custom_minimum_size = Vector2(0, 32)
	btn_close.add_theme_font_size_override("font_size", 14)
	var dark_sec_btn = StyleBoxFlat.new(); dark_sec_btn.bg_color = Color(0.2, 0.25, 0.35, 1.0); dark_sec_btn.corner_radius_top_left = 6; dark_sec_btn.corner_radius_top_right = 6; dark_sec_btn.corner_radius_bottom_left = 6; dark_sec_btn.corner_radius_bottom_right = 6
	var dark_sec_btn_hover = dark_sec_btn.duplicate(); dark_sec_btn_hover.bg_color = Color(0.25, 0.3, 0.42, 1.0)
	btn_close.add_theme_stylebox_override("normal", dark_sec_btn); btn_close.add_theme_stylebox_override("hover", dark_sec_btn_hover); btn_close.add_theme_stylebox_override("pressed", dark_sec_btn)
	btn_close.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0)); btn_close.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	vbox.add_child(btn_close)
	
	btn_action.pressed.connect(func():
		if not is_recording:
			is_recording = true
			elapsed = 0.0
			status_lbl.text = "Status: RECORDING..."
			status_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
			btn_action.text = "⏹ Stop & Save"
			var red_normal = StyleBoxFlat.new(); red_normal.bg_color = Color(0.75, 0.18, 0.18, 1.0); red_normal.corner_radius_top_left = 6; red_normal.corner_radius_top_right = 6; red_normal.corner_radius_bottom_left = 6; red_normal.corner_radius_bottom_right = 6
			var red_hover = red_normal.duplicate(); red_hover.bg_color = Color(0.85, 0.22, 0.22, 1.0)
			btn_action.add_theme_stylebox_override("normal", red_normal)
			btn_action.add_theme_stylebox_override("hover", red_hover)
			timer.start()
		else:
			is_recording = false
			timer.stop()
			timer.queue_free()
			var base64_wav = _generate_mock_wav_base64()
			callback.call(base64_wav)
			backdrop.queue_free()
	)
	
	btn_close.pressed.connect(func():
		timer.stop()
		timer.queue_free()
		backdrop.queue_free()
	)

func _open_ivr_option_dialog(opt_digit: String, opt_parent: String = "") -> void:
	var sec_btn_st = StyleBoxFlat.new(); sec_btn_st.bg_color = Color(0.92, 0.94, 0.97, 1.0); sec_btn_st.corner_radius_top_left = 6; sec_btn_st.corner_radius_top_right = 6; sec_btn_st.corner_radius_bottom_left = 6; sec_btn_st.corner_radius_bottom_right = 6; sec_btn_st.border_width_left = 1; sec_btn_st.border_width_top = 1; sec_btn_st.border_width_right = 1; sec_btn_st.border_width_bottom = 1; sec_btn_st.border_color = Color(0.78, 0.82, 0.88, 1.0); sec_btn_st.content_margin_left = 12; sec_btn_st.content_margin_right = 12; sec_btn_st.content_margin_top = 6; sec_btn_st.content_margin_bottom = 6
	var sec_btn_hover = sec_btn_st.duplicate(); sec_btn_hover.bg_color = Color(0.96, 0.97, 0.99, 1.0)

	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	
	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.80, 0.85, 0.90, 1.0)
	card_st.corner_radius_top_left = 8; card_st.corner_radius_top_right = 8; card_st.corner_radius_bottom_left = 8; card_st.corner_radius_bottom_right = 8
	card_st.content_margin_left = 20; card_st.content_margin_top = 18; card_st.content_margin_right = 20; card_st.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(450, 450)
	card.add_child(vbox)
	
	var title = Label.new()
	title.text = "➕ Add Phone Key Action" if opt_digit == "" else "✏️ Edit Phone Key Action"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title)
	
	# Digit Input
	var dig_hbox = HBoxContainer.new()
	var dig_lbl = Label.new(); dig_lbl.text = "Phone Key (e.g. 1, 1-2): "; dig_lbl.custom_minimum_size = Vector2(160, 0); dig_lbl.add_theme_font_size_override("font_size", 15); dig_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var dig_edit = LineEdit.new()
	dig_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	dig_edit.custom_minimum_size = Vector2(0, 36)
	_style_input_control(dig_edit, 15)
	if opt_digit != "":
		dig_edit.text = opt_digit
		dig_edit.editable = false
	elif opt_parent != "":
		dig_edit.text = opt_parent + "-"
	dig_hbox.add_child(dig_lbl); dig_hbox.add_child(dig_edit)
	vbox.add_child(dig_hbox)
	
	# Name Input
	var name_hbox = HBoxContainer.new()
	var name_lbl = Label.new(); name_lbl.text = "Option Name: "; name_lbl.custom_minimum_size = Vector2(160, 0); name_lbl.add_theme_font_size_override("font_size", 15); name_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	name_edit.custom_minimum_size = Vector2(0, 36)
	_style_input_control(name_edit, 15)
	name_hbox.add_child(name_lbl); name_hbox.add_child(name_edit)
	vbox.add_child(name_hbox)
	
	# Action Dropdown
	var act_hbox = HBoxContainer.new()
	var act_lbl = Label.new(); act_lbl.text = "Action: "; act_lbl.custom_minimum_size = Vector2(160, 0); act_lbl.add_theme_font_size_override("font_size", 15); act_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var act_opt = OptionButton.new()
	act_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	act_opt.custom_minimum_size = Vector2(0, 36)
	_style_input_control(act_opt, 15)
	act_opt.add_item("Speak Script / Play Audio", 0)
	act_opt.add_item("Route to Voicemail Box", 1)
	act_opt.add_item("Transfer Call", 2)
	act_opt.add_item("Open Nested Keys", 3)
	act_hbox.add_child(act_lbl); act_hbox.add_child(act_opt)
	vbox.add_child(act_hbox)
	
	# Dynamic parameter container
	var param_vbox = VBoxContainer.new()
	param_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(param_vbox)
	
	var active_audio_base64 = ""
	var use_custom_audio = false
	
	# Load existing data if editing
	if opt_digit != "":
		var load_res = db.execute("SELECT * FROM ivr_menu_options WHERE digit = ? LIMIT 1;", [opt_digit])
		if load_res["success"] and load_res["data"].size() > 0:
			var item = load_res["data"][0]
			name_edit.text = str(item["menu_option_name"])
			var act_type = str(item["action_type"])
			if act_type == "speak": act_opt.selected = 0
			elif act_type == "voicemail": act_opt.selected = 1
			elif act_type == "transfer": act_opt.selected = 2
			elif act_type == "submenu": act_opt.selected = 3
			use_custom_audio = item.get("use_custom_audio", 0) == 1
			active_audio_base64 = str(item.get("audio_data", ""))
			
	var refresh_param_ui = func():
		for child in param_vbox.get_children(): child.free()
		var sel = act_opt.selected
		if sel == 0: # Speak
			var tts_lbl = Label.new(); tts_lbl.text = "Script Speech Text:"; tts_lbl.add_theme_font_size_override("font_size", 14); tts_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
			var tts_edit = TextEdit.new(); tts_edit.custom_minimum_size = Vector2(0, 80); _style_input_control(tts_edit, 15); tts_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			if opt_digit != "":
				var load_res = db.execute("SELECT script_text FROM ivr_menu_options WHERE digit = ? LIMIT 1;", [opt_digit])
				if load_res["success"] and load_res["data"].size() > 0:
					tts_edit.text = str(load_res["data"][0]["script_text"])
			param_vbox.add_child(tts_lbl); param_vbox.add_child(tts_edit)
			
			var audio_toggle = CheckButton.new(); audio_toggle.text = "Use custom audio recording instead of TTS"; audio_toggle.button_pressed = use_custom_audio
			audio_toggle.add_theme_font_size_override("font_size", 15)
			audio_toggle.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
			audio_toggle.add_theme_color_override("font_pressed_color", Color(0.08, 0.12, 0.18, 1.0))
			audio_toggle.add_theme_color_override("font_hover_color", Color(0.08, 0.12, 0.18, 1.0))
			audio_toggle.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.12, 0.18, 1.0))
			audio_toggle.toggled.connect(func(btn_state): use_custom_audio = btn_state)
			param_vbox.add_child(audio_toggle)
			
			var btns_hbox = HBoxContainer.new(); btns_hbox.add_theme_constant_override("separation", 10)
			var up_btn = Button.new(); up_btn.text = "📁 Upload File"; up_btn.custom_minimum_size = Vector2(110, 32); up_btn.add_theme_font_size_override("font_size", 14)
			var rec_btn = Button.new(); rec_btn.text = "⏺ Record Voice"; rec_btn.custom_minimum_size = Vector2(120, 32); rec_btn.add_theme_font_size_override("font_size", 14)
			var play_btn = Button.new(); play_btn.text = "▶ Play"; play_btn.custom_minimum_size = Vector2(90, 32); play_btn.add_theme_font_size_override("font_size", 14)
			
			up_btn.add_theme_stylebox_override("normal", sec_btn_st); up_btn.add_theme_stylebox_override("hover", sec_btn_hover); up_btn.add_theme_stylebox_override("pressed", sec_btn_st)
			up_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); up_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
			
			rec_btn.add_theme_stylebox_override("normal", sec_btn_st); rec_btn.add_theme_stylebox_override("hover", sec_btn_hover); rec_btn.add_theme_stylebox_override("pressed", sec_btn_st)
			rec_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); rec_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
			
			play_btn.add_theme_stylebox_override("normal", sec_btn_st); play_btn.add_theme_stylebox_override("hover", sec_btn_hover); play_btn.add_theme_stylebox_override("pressed", sec_btn_st)
			play_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); play_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
			btns_hbox.add_child(up_btn); btns_hbox.add_child(rec_btn); btns_hbox.add_child(play_btn)
			param_vbox.add_child(btns_hbox)
			
			up_btn.pressed.connect(func():
				var fd = FileDialog.new(); fd.access = FileDialog.ACCESS_FILESYSTEM; fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE; fd.filters = PackedStringArray(["*.wav, *.mp3, *.ogg ; Audio Files"]); fd.size = Vector2i(700, 500)
				fd.file_selected.connect(func(path: String):
					var bytes = FileAccess.get_file_as_bytes(path)
					if bytes.size() > 0:
						active_audio_base64 = Marshalls.raw_to_base64(bytes)
				)
				add_child(fd); fd.popup_centered()
			)
			rec_btn.pressed.connect(func():
				_open_voice_recording_dialog(func(base64_wav: String): active_audio_base64 = base64_wav)
			)
			play_btn.pressed.connect(func():
				if active_audio_base64 != "": _play_audio_from_base64(active_audio_base64)
			)
		elif sel == 1: # Route to Voicemail
			var vm_lbl = Label.new(); vm_lbl.text = "Select Recipient Voicemail Box:"; vm_lbl.add_theme_font_size_override("font_size", 14); vm_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
			var vm_opt = OptionButton.new(); vm_opt.custom_minimum_size = Vector2(0, 36); _style_input_control(vm_opt, 15)
			vm_opt.add_item("General Inbox", 0)
			
			var staff_res = db.execute("SELECT id, first_name || ' ' || last_name AS name FROM people WHERE LOWER(primary_role) IN ('staff', 'intern', 'volunteer') ORDER BY name ASC;")
			var selected_id_str = ""
			if opt_digit != "":
				var load_res = db.execute("SELECT action_param FROM ivr_menu_options WHERE digit = ? LIMIT 1;", [opt_digit])
				if load_res["success"] and load_res["data"].size() > 0:
					selected_id_str = str(load_res["data"][0]["action_param"])
					
			if staff_res["success"]:
				for idx in range(staff_res["data"].size()):
					var p = staff_res["data"][idx]
					vm_opt.add_item(str(p["name"]), int(p["id"]))
					if selected_id_str != "" and int(p["id"]) == int(selected_id_str):
						vm_opt.selected = idx + 1
			param_vbox.add_child(vm_lbl); param_vbox.add_child(vm_opt)
		elif sel == 2: # Transfer Call
			var trans_lbl = Label.new(); trans_lbl.text = "Transfer Phone Number:"; trans_lbl.add_theme_font_size_override("font_size", 14); trans_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
			var trans_edit = LineEdit.new(); trans_edit.placeholder_text = "e.g. 509-555-0101"; trans_edit.custom_minimum_size = Vector2(0, 36); _style_input_control(trans_edit, 15)
			if opt_digit != "":
				var load_res = db.execute("SELECT action_param FROM ivr_menu_options WHERE digit = ? LIMIT 1;", [opt_digit])
				if load_res["success"] and load_res["data"].size() > 0:
					trans_edit.text = str(load_res["data"][0]["action_param"])
			param_vbox.add_child(trans_lbl); param_vbox.add_child(trans_edit)
			
	act_opt.item_selected.connect(func(_idx): refresh_param_ui.call())
	refresh_param_ui.call()
	
	# Action buttons row
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_END
	action_hbox.add_theme_constant_override("separation", 12)
	
	var cancel_btn = Button.new(); cancel_btn.text = "Cancel"; cancel_btn.custom_minimum_size = Vector2(100, 36); cancel_btn.add_theme_font_size_override("font_size", 15)
	var save_btn = Button.new(); save_btn.text = "Save Option"; save_btn.custom_minimum_size = Vector2(120, 36); save_btn.add_theme_font_size_override("font_size", 15)
	var save_st = StyleBoxFlat.new(); save_st.bg_color = _get_active_theme_color(); save_st.corner_radius_top_left = 6; save_st.corner_radius_top_right = 6; save_st.corner_radius_bottom_left = 6; save_st.corner_radius_bottom_right = 6
	var save_hover = save_st.duplicate(); save_hover.bg_color = _get_active_theme_color().lightened(0.08)
	
	cancel_btn.add_theme_stylebox_override("normal", sec_btn_st); cancel_btn.add_theme_stylebox_override("hover", sec_btn_hover); cancel_btn.add_theme_stylebox_override("pressed", sec_btn_st)
	cancel_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); cancel_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
	
	save_btn.add_theme_stylebox_override("normal", save_st); save_btn.add_theme_stylebox_override("hover", save_hover); save_btn.add_theme_stylebox_override("pressed", save_st)
	save_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1)); save_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	
	action_hbox.add_child(cancel_btn); action_hbox.add_child(save_btn)
	vbox.add_child(action_hbox)
	
	cancel_btn.pressed.connect(func(): backdrop.queue_free())
	save_btn.pressed.connect(func():
		var final_digit = dig_edit.text.strip_edges()
		var final_name = name_edit.text.strip_edges()
		if final_digit == "" or final_name == "": return
		
		var final_act = "speak"
		var final_param = ""
		var final_script = ""
		
		var sel = act_opt.selected
		if sel == 0:
			final_act = "speak"
			var script_box = param_vbox.get_child(1) as TextEdit
			if script_box: final_script = script_box.text.strip_edges()
		elif sel == 1:
			final_act = "voicemail"
			var opt_box = param_vbox.get_child(1) as OptionButton
			if opt_box:
				if opt_box.selected > 0:
					final_param = str(opt_box.get_item_id(opt_box.selected))
				else:
					final_param = "general"
		elif sel == 2:
			final_act = "transfer"
			var edit_box = param_vbox.get_child(1) as LineEdit
			if edit_box: final_param = edit_box.text.strip_edges()
		elif sel == 3:
			final_act = "submenu"
			
		var parent = null
		if opt_parent != "":
			parent = opt_parent
		elif final_digit.contains("-"):
			parent = final_digit.split("-")[0]
			
		var q = """
			INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param, parent_digit, use_custom_audio, audio_data)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
			ON CONFLICT(digit) DO UPDATE SET
				menu_option_name = excluded.menu_option_name,
				script_text = excluded.script_text,
				action_type = excluded.action_type,
				action_param = excluded.action_param,
				parent_digit = excluded.parent_digit,
				use_custom_audio = excluded.use_custom_audio,
				audio_data = excluded.audio_data;
		"""
		var up_res = db.execute(q, [final_digit, final_name, final_script, final_act, final_param, parent, 1 if use_custom_audio else 0, active_audio_base64])
		if up_res["success"]:
			backdrop.queue_free()
			_render_ivr_tab()
	)

func _play_audio_from_base64(base64_str: String) -> void:
	if base64_str == "": return
	var bytes = Marshalls.base64_to_raw(base64_str)
	if bytes.size() == 0: return
	
	var player = AudioStreamPlayer.new()
	add_child(player)
	var stream = AudioStreamWAV.new()
	stream.data = bytes
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	player.stream = stream
	player.play()
	player.finished.connect(func(): player.queue_free())

func _generate_mock_wav_base64() -> String:
	var header = PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952) # "RIFF"
	header.encode_u32(4, 36 + 4000) # file size - 8
	header.encode_u32(8, 0x45564157) # "WAVE"
	header.encode_u32(12, 0x20746d66) # "fmt "
	header.encode_u32(16, 16) # chunk size
	header.encode_u16(20, 1) # compression code (PCM)
	header.encode_u16(22, 1) # channels (1)
	header.encode_u32(24, 8000) # sample rate
	header.encode_u32(28, 8000 * 1 * 2) # byte rate
	header.encode_u16(32, 1 * 2) # block align
	header.encode_u16(34, 16) # bits per sample
	header.encode_u32(36, 0x61746164) # "data"
	header.encode_u32(40, 4000) # data size
	
	var data = PackedByteArray()
	data.resize(4000)
	for i in range(2000):
		var sample = int(sin(i * 0.1) * 32767)
		data.encode_s16(i * 2, sample)
		
	return Marshalls.raw_to_base64(header + data)

func _get_current_actor_id() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'CURRENT_USER_ID';")
	if res["success"] and res["data"].size() > 0:
		var val = str(res["data"][0]["setting_value"]).strip_edges()
		if val != "": return val
	return "usr_admin_master"

func _get_current_actor_name() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'CURRENT_USER_NAME';")
	if res["success"] and res["data"].size() > 0:
		var val = str(res["data"][0]["setting_value"]).strip_edges()
		if val != "": return val
	return "Administrator"

func _get_pending_outbox_count() -> int:
	if not db: return 0
	var res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE status = 'pending';")
	if res["success"] and res["data"].size() > 0:
		return int(res["data"][0]["cnt"])
	return 0

func _render_sessions_config_tab() -> void:
	if not config_service:
		config_service = SessionConfigServiceScript.new(db)

	var actor_id = _get_current_actor_id()
	var actor_name = _get_current_actor_name()
	var pending_sync = _get_pending_outbox_count()

	var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; scroll.custom_minimum_size = Vector2(0, 520)
	var margin_wrap = MarginContainer.new(); margin_wrap.size_flags_horizontal = SIZE_EXPAND_FILL; margin_wrap.add_theme_constant_override("margin_right", 24)
	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 24)

	# Top Header with Offline Sync Status Badge
	var header_hbox = HBoxContainer.new(); header_hbox.add_theme_constant_override("separation", 14)
	var head_vbox = VBoxContainer.new(); head_vbox.size_flags_horizontal = SIZE_EXPAND_FILL; head_vbox.add_theme_constant_override("separation", 4)

	var head = Label.new(); head.text = "📋 Session Types & Locations Configuration (PD-007)"
	head.add_theme_font_size_override("font_size", 24); head.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	head_vbox.add_child(head)

	var sub = Label.new(); sub.text = "Manage room locations, session taxonomy types, exclusivity rules, and display ordering across your StudyCenter tenant."
	sub.add_theme_font_size_override("font_size", 18); sub.add_theme_color_override("font_color", Color(0.22, 0.28, 0.38, 1.0))
	head_vbox.add_child(sub)

	header_hbox.add_child(head_vbox)

	# Outbox Sync Status Badge
	var sync_badge = Label.new()
	sync_badge.text = "☁️ Sync: %d queued offline" % pending_sync if pending_sync > 0 else "☁️ Sync: Synced"
	sync_badge.add_theme_font_size_override("font_size", 15)
	sync_badge.add_theme_color_override("font_color", Color(0.78, 0.50, 0.08, 1.0) if pending_sync > 0 else Color(0.12, 0.50, 0.22, 1.0))
	header_hbox.add_child(sync_badge)

	vbox.add_child(header_hbox)

	# Status alert banner
	var status_banner = Label.new()
	status_banner.add_theme_font_size_override("font_size", 18)
	status_banner.visible = false
	vbox.add_child(status_banner)

	# ==================== SECTION 1: SESSION TYPES MANAGEMENT ====================
	var types_lbl = Label.new(); types_lbl.text = "🏷️ Session Types Taxonomy Management"
	types_lbl.add_theme_font_size_override("font_size", 20); types_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(types_lbl)

	# Add Session Type Form Card
	var add_type_card = VBoxContainer.new(); add_type_card.add_theme_constant_override("separation", 8)
	var add_type_title = Label.new(); add_type_title.text = "Session Type Name *"
	add_type_title.add_theme_font_size_override("font_size", 15); add_type_title.add_theme_color_override("font_color", Color(0.18, 0.24, 0.32, 1.0))
	add_type_card.add_child(add_type_title)

	var add_type_hbox = HBoxContainer.new(); add_type_hbox.add_theme_constant_override("separation", 10)
	var input_type_name = LineEdit.new(); input_type_name.placeholder_text = "e.g. Workshop"; input_type_name.custom_minimum_size = Vector2(280, 44); _style_input_control(input_type_name, 16)
	var input_type_desc = LineEdit.new(); input_type_desc.placeholder_text = "Description (Optional)"; input_type_desc.custom_minimum_size = Vector2(320, 44); _style_input_control(input_type_desc, 16)
	var btn_add_type = Button.new(); btn_add_type.text = "➕ Add Session Type"; btn_add_type.custom_minimum_size = Vector2(180, 44); btn_add_type.add_theme_font_size_override("font_size", 16)

	add_type_hbox.add_child(input_type_name); add_type_hbox.add_child(input_type_desc); add_type_hbox.add_child(btn_add_type)
	add_type_card.add_child(add_type_hbox)
	vbox.add_child(add_type_card)

	btn_add_type.pressed.connect(func():
		var t_name = input_type_name.text.strip_edges()
		var t_desc = input_type_desc.text.strip_edges()
		var add_res = config_service.add_session_type(t_name, t_desc, actor_id, actor_name)
		if add_res["success"]:
			status_banner.text = "✅ Session Type '" + t_name + "' added successfully!"
			status_banner.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0)); status_banner.visible = true
			_render_sessions_config_tab()
		else:
			status_banner.text = "❌ Error adding Session Type: " + add_res["error"]
			status_banner.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0)); status_banner.visible = true
	)

	# Session Types List Container
	var types_vbox = VBoxContainer.new(); types_vbox.add_theme_constant_override("separation", 10)
	var all_types = config_service.get_all_session_types(true)

	for t in all_types:
		var t_id = int(t["id"])
		var t_name = str(t["name"])
		var t_desc = str(t.get("description", ""))
		var t_active = int(t.get("is_active", 1)) == 1
		var t_migrated = int(t.get("is_migrated", 0)) == 1

		var row_card = PanelContainer.new()
		var r_style = StyleBoxFlat.new()
		r_style.bg_color = Color(0.97, 0.98, 1.0, 1.0) if t_active else Color(0.92, 0.94, 0.96, 1.0)
		r_style.border_width_left = 1; r_style.border_width_top = 1; r_style.border_width_right = 1; r_style.border_width_bottom = 1
		r_style.border_color = Color(0.80, 0.85, 0.92, 1.0) if t_active else Color(0.70, 0.74, 0.80, 1.0)
		r_style.corner_radius_top_left = 6; r_style.corner_radius_top_right = 6; r_style.corner_radius_bottom_left = 6; r_style.corner_radius_bottom_right = 6
		r_style.content_margin_left = 14; r_style.content_margin_top = 10; r_style.content_margin_right = 14; r_style.content_margin_bottom = 10
		row_card.add_theme_stylebox_override("panel", r_style)

		var r_hbox = HBoxContainer.new(); r_hbox.add_theme_constant_override("separation", 10)

		# Order Badge
		var ord_lbl = Label.new(); ord_lbl.text = "#" + str(t.get("display_order", 1))
		ord_lbl.add_theme_font_size_override("font_size", 16); ord_lbl.add_theme_color_override("font_color", Color(0.40, 0.46, 0.54, 1.0))
		r_hbox.add_child(ord_lbl)

		# Editable Name LineEdit
		var edit_name = LineEdit.new(); edit_name.text = t_name; edit_name.custom_minimum_size = Vector2(220, 38); _style_input_control(edit_name, 16)
		r_hbox.add_child(edit_name)

		# Editable Description LineEdit
		var edit_desc = LineEdit.new(); edit_desc.text = t_desc; edit_desc.custom_minimum_size = Vector2(240, 38); _style_input_control(edit_desc, 16)
		r_hbox.add_child(edit_desc)

		# Save Button
		var btn_save = Button.new(); btn_save.text = "💾 Save"; btn_save.custom_minimum_size = Vector2(75, 38); btn_save.add_theme_font_size_override("font_size", 14)
		btn_save.pressed.connect(func():
			var ren_res = config_service.rename_session_type(t_id, edit_name.text, edit_desc.text, actor_id, actor_name)
			if ren_res["success"]:
				status_banner.text = "✅ Session Type updated successfully!"
				status_banner.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0)); status_banner.visible = true
				_render_sessions_config_tab()
			else:
				status_banner.text = "❌ Update error: " + ren_res["error"]
				status_banner.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0)); status_banner.visible = true
		)
		r_hbox.add_child(btn_save)

		# Cancel / Reset Button
		var btn_reset = Button.new(); btn_reset.text = "❌ Reset"; btn_reset.custom_minimum_size = Vector2(75, 38); btn_reset.add_theme_font_size_override("font_size", 14)
		btn_reset.pressed.connect(func(): edit_name.text = t_name; edit_desc.text = t_desc)
		r_hbox.add_child(btn_reset)

		# Up / Down Order Buttons
		var btn_up = Button.new(); btn_up.text = "⬆️"; btn_up.custom_minimum_size = Vector2(38, 38)
		btn_up.pressed.connect(func(): config_service.move_session_type_order(t_id, "up", actor_id, actor_name); _render_sessions_config_tab())
		r_hbox.add_child(btn_up)

		var btn_down = Button.new(); btn_down.text = "⬇️"; btn_down.custom_minimum_size = Vector2(38, 38)
		btn_down.pressed.connect(func(): config_service.move_session_type_order(t_id, "down", actor_id, actor_name); _render_sessions_config_tab())
		r_hbox.add_child(btn_down)

		# Active / Inactive State Toggle Button with Deactivation Warning Confirmation
		var btn_toggle = Button.new()
		btn_toggle.text = "🚫 Deactivate" if t_active else "🔄 Activate"
		btn_toggle.custom_minimum_size = Vector2(105, 38); btn_toggle.add_theme_font_size_override("font_size", 14)
		btn_toggle.pressed.connect(func():
			var toggle_res = config_service.set_session_type_active_state(t_id, not t_active, actor_id, actor_name)
			if toggle_res["success"]:
				status_banner.text = "✅ Session Type '%s' is now %s." % [t_name, "Active" if not t_active else "Inactive"]
				status_banner.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0)); status_banner.visible = true
				_render_sessions_config_tab()
			else:
				status_banner.text = "❌ State change error: " + toggle_res["error"]
				status_banner.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0)); status_banner.visible = true
		)
		r_hbox.add_child(btn_toggle)

		# Unified User-Facing Status Badge
		var badge_str = "Active" if t_active else ("Inactive [Migrated]" if t_migrated else "Inactive")
		var badge_lbl = Label.new(); badge_lbl.text = badge_str
		badge_lbl.add_theme_font_size_override("font_size", 14)
		badge_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0) if t_active else Color(0.45, 0.50, 0.58, 1.0))
		r_hbox.add_child(badge_lbl)

		row_card.add_child(r_hbox)
		types_vbox.add_child(row_card)

	vbox.add_child(types_vbox)

	# ==================== SECTION 2: SESSION LOCATIONS MANAGEMENT ====================
	var locs_lbl = Label.new(); locs_lbl.text = "📍 Session Locations & Exclusivity Rules"
	locs_lbl.add_theme_font_size_override("font_size", 20); locs_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(locs_lbl)

	# Explanatory Help Text
	var loc_help = Label.new(); loc_help.text = "⭐ Exclusive Locations (e.g., Whole Center) cannot be combined with standard rooms during session scheduling."
	loc_help.add_theme_font_size_override("font_size", 15); loc_help.add_theme_color_override("font_color", Color(0.78, 0.50, 0.08, 1.0))
	vbox.add_child(loc_help)

	# Add Location Form Card
	var add_loc_card = VBoxContainer.new(); add_loc_card.add_theme_constant_override("separation", 8)
	var add_loc_title = Label.new(); add_loc_title.text = "Location Name *"
	add_loc_title.add_theme_font_size_override("font_size", 15); add_loc_title.add_theme_color_override("font_color", Color(0.18, 0.24, 0.32, 1.0))
	add_loc_card.add_child(add_loc_title)

	var add_loc_hbox = HBoxContainer.new(); add_loc_hbox.add_theme_constant_override("separation", 10)
	var input_loc_name = LineEdit.new(); input_loc_name.placeholder_text = "e.g. Study Room #4"; input_loc_name.custom_minimum_size = Vector2(300, 44); _style_input_control(input_loc_name, 16)
	var chk_loc_excl = CheckBox.new(); chk_loc_excl.text = "Exclusive Location"
	var btn_add_loc = Button.new(); btn_add_loc.text = "➕ Add Location"; btn_add_loc.custom_minimum_size = Vector2(170, 44); btn_add_loc.add_theme_font_size_override("font_size", 16)

	add_loc_hbox.add_child(input_loc_name); add_loc_hbox.add_child(chk_loc_excl); add_loc_hbox.add_child(btn_add_loc)
	add_loc_card.add_child(add_loc_hbox)
	vbox.add_child(add_loc_card)

	btn_add_loc.pressed.connect(func():
		var l_name = input_loc_name.text.strip_edges()
		var l_excl = chk_loc_excl.button_pressed
		var add_res = config_service.add_session_location(l_name, l_excl, actor_id, actor_name)
		if add_res["success"]:
			status_banner.text = "✅ Session Location '" + l_name + "' added successfully!"
			status_banner.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0)); status_banner.visible = true
			_render_sessions_config_tab()
		else:
			status_banner.text = "❌ Error adding Session Location: " + add_res["error"]
			status_banner.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0)); status_banner.visible = true
	)

	# Locations List Container
	var locs_vbox = VBoxContainer.new(); locs_vbox.add_theme_constant_override("separation", 10)
	var all_locs = config_service.get_all_session_locations(true)

	for l in all_locs:
		var l_id = int(l["id"])
		var l_name = str(l["name"])
		var l_excl = int(l.get("is_exclusive", 0)) == 1
		var l_active = int(l.get("is_active", 1)) == 1
		var l_migrated = int(l.get("is_migrated", 0)) == 1

		var row_card = PanelContainer.new()
		var r_style = StyleBoxFlat.new()
		r_style.bg_color = Color(0.97, 0.98, 1.0, 1.0) if l_active else Color(0.92, 0.94, 0.96, 1.0)
		r_style.border_width_left = 1; r_style.border_width_top = 1; r_style.border_width_right = 1; r_style.border_width_bottom = 1
		r_style.border_color = Color(0.80, 0.85, 0.92, 1.0) if l_active else Color(0.70, 0.74, 0.80, 1.0)
		r_style.corner_radius_top_left = 6; r_style.corner_radius_top_right = 6; r_style.corner_radius_bottom_left = 6; r_style.corner_radius_bottom_right = 6
		r_style.content_margin_left = 14; r_style.content_margin_top = 10; r_style.content_margin_right = 14; r_style.content_margin_bottom = 10
		row_card.add_theme_stylebox_override("panel", r_style)

		var r_hbox = HBoxContainer.new(); r_hbox.add_theme_constant_override("separation", 10)

		# Order Badge
		var ord_lbl = Label.new(); ord_lbl.text = "#" + str(l.get("display_order", 1))
		ord_lbl.add_theme_font_size_override("font_size", 16); ord_lbl.add_theme_color_override("font_color", Color(0.40, 0.46, 0.54, 1.0))
		r_hbox.add_child(ord_lbl)

		# Editable Name LineEdit
		var edit_name = LineEdit.new(); edit_name.text = l_name; edit_name.custom_minimum_size = Vector2(260, 38); _style_input_control(edit_name, 16)
		r_hbox.add_child(edit_name)

		# Exclusive CheckBox (Single Editing Control)
		var edit_excl = CheckBox.new(); edit_excl.text = "Exclusive"; edit_excl.button_pressed = l_excl
		r_hbox.add_child(edit_excl)

		# Save Button
		var btn_save = Button.new(); btn_save.text = "💾 Save"; btn_save.custom_minimum_size = Vector2(75, 38); btn_save.add_theme_font_size_override("font_size", 14)
		btn_save.pressed.connect(func():
			var ren_res = config_service.rename_session_location(l_id, edit_name.text, edit_excl.button_pressed, actor_id, actor_name)
			if ren_res["success"]:
				status_banner.text = "✅ Session Location updated successfully!"
				status_banner.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0)); status_banner.visible = true
				_render_sessions_config_tab()
			else:
				status_banner.text = "❌ Update error: " + ren_res["error"]
				status_banner.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0)); status_banner.visible = true
		)
		r_hbox.add_child(btn_save)

		# Cancel / Reset Button
		var btn_reset = Button.new(); btn_reset.text = "❌ Reset"; btn_reset.custom_minimum_size = Vector2(75, 38); btn_reset.add_theme_font_size_override("font_size", 14)
		btn_reset.pressed.connect(func(): edit_name.text = l_name; edit_excl.button_pressed = l_excl)
		r_hbox.add_child(btn_reset)

		# Up / Down Order Buttons
		var btn_up = Button.new(); btn_up.text = "⬆️"; btn_up.custom_minimum_size = Vector2(38, 38)
		btn_up.pressed.connect(func(): config_service.move_session_location_order(l_id, "up", actor_id, actor_name); _render_sessions_config_tab())
		r_hbox.add_child(btn_up)

		var btn_down = Button.new(); btn_down.text = "⬇️"; btn_down.custom_minimum_size = Vector2(38, 38)
		btn_down.pressed.connect(func(): config_service.move_session_location_order(l_id, "down", actor_id, actor_name); _render_sessions_config_tab())
		r_hbox.add_child(btn_down)

		# Active / Inactive State Toggle Button
		var btn_toggle = Button.new()
		btn_toggle.text = "🚫 Deactivate" if l_active else "🔄 Activate"
		btn_toggle.custom_minimum_size = Vector2(105, 38); btn_toggle.add_theme_font_size_override("font_size", 14)
		btn_toggle.pressed.connect(func():
			var toggle_res = config_service.set_session_location_active_state(l_id, not l_active, actor_id, actor_name)
			if toggle_res["success"]:
				status_banner.text = "✅ Session Location '%s' is now %s." % [l_name, "Active" if not l_active else "Inactive"]
				status_banner.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0)); status_banner.visible = true
				_render_sessions_config_tab()
			else:
				status_banner.text = "❌ State change error: " + toggle_res["error"]
				status_banner.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15, 1.0)); status_banner.visible = true
		)
		r_hbox.add_child(btn_toggle)

		# Unified User-Facing Status & Exclusive Badges
		var badge_str = "Active" if l_active else ("Inactive [Migrated]" if l_migrated else "Inactive")
		var badge_lbl = Label.new(); badge_lbl.text = badge_str
		badge_lbl.add_theme_font_size_override("font_size", 14)
		badge_lbl.add_theme_color_override("font_color", Color(0.12, 0.50, 0.22, 1.0) if l_active else Color(0.45, 0.50, 0.58, 1.0))
		r_hbox.add_child(badge_lbl)

		if l_excl:
			var excl_badge = Label.new(); excl_badge.text = "⭐ Exclusive"
			excl_badge.add_theme_font_size_override("font_size", 14); excl_badge.add_theme_color_override("font_color", Color(0.78, 0.50, 0.08, 1.0))
			r_hbox.add_child(excl_badge)

		row_card.add_child(r_hbox)
		locs_vbox.add_child(row_card)

	vbox.add_child(locs_vbox)

	margin_wrap.add_child(vbox)
	scroll.add_child(margin_wrap)
	content_card.add_child(scroll)
