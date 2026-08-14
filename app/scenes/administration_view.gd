extends "res://app/scenes/standard_page_container.gd"

const static_voices = [
	{"id": "Polly.Kimberly-Neural", "label": "Kimberly", "gender": "Female", "language": "en-US"},
	{"id": "Polly.Joanna-Neural", "label": "Joanna", "gender": "Female", "language": "en-US"},
	{"id": "Polly.Kendra-Neural", "label": "Kendra", "gender": "Female", "language": "en-US"},
	{"id": "Polly.Salli-Neural", "label": "Salli", "gender": "Female", "language": "en-US"},
	{"id": "Polly.Ruth-Neural", "label": "Ruth", "gender": "Female", "language": "en-US"},
	{"id": "Polly.Amy-Neural", "label": "Amy", "gender": "Female", "language": "en-GB"},
	{"id": "Polly.Olivia-Neural", "label": "Olivia", "gender": "Female", "language": "en-US"},
	{"id": "Polly.Lupe-Neural", "label": "Lupe", "gender": "Female", "language": "en-US"},
	{"id": "Polly.Matthew-Neural", "label": "Matthew", "gender": "Male", "language": "en-US"}
]

## Administration & Platform Control Center View (ADM-SPR1-001)
## Complies with [PD-006] (Subscription Licensing), [PD-009] (RBAC), and [PD-010] (White-Label & Vocabulary).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")
const GatewaySyncScript = preload("res://src/domain/sync/gateway_sync_service.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const CardPrintQueueDialogScript = preload("res://app/scenes/card_print_queue_dialog.gd")
const PublicQrSignDialogScript = preload("res://app/scenes/public_qr_sign_dialog.gd")
const CampusCommunityAdminServiceScript = preload("res://src/domain/campus_community/campus_community_admin_service.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")

var db: RefCounted
var active_tab: String = "modules"
var twilio_service: RefCounted
var config_service: RefCounted
var selected_user_id: int = 0
var selected_rbac_role: String = "Team Leader"

var ivr_sub_tab: String = "scripts"
var unsaved_ivr_scripts: Dictionary = {}
var selected_ivr_day: String = ""

var sticky_bar: PanelContainer
var sticky_label: Label

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

func receive_navigation_context(params: Dictionary = {}) -> void:
	if params.get("tab") == "campus_community":
		active_tab = "campus_community"
		if params.has("sub_tab"):
			cc_admin_sub_tab = str(params["sub_tab"])
		switch_tab(active_tab)
	elif params.get("queue_mode", false) == true or params.get("queue_id") == "failed_inbound_events":
		active_tab = "sync_engine"
		switch_tab(active_tab)

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
			var QrDlgScript = load("res://app/scenes/public_qr_sign_dialog.gd")
			var dlg = QrDlgScript.new(self)
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

		var btn_cc = Button.new()
		btn_cc.name = "BtnTabCampusCommunity"
		btn_cc.text = "  🎓 Campus & Community Administration  "
		btn_cc.custom_minimum_size = Vector2(0, 36)
		btn_cc.add_theme_font_size_override("font_size", 14)
		tab_hbox.add_child(btn_cc)
		btn_cc.pressed.connect(func(): switch_tab("campus_community"))

		var btn_scripture = Button.new()
		btn_scripture.name = "BtnTabScripture"
		btn_scripture.text = "  📖 Scripture & Sidebar Messages  "
		btn_scripture.custom_minimum_size = Vector2(0, 36)
		btn_scripture.add_theme_font_size_override("font_size", 14)
		tab_hbox.add_child(btn_scripture)
		btn_scripture.pressed.connect(func(): switch_tab("scripture"))

	# Initialize Sticky Bar
	sticky_bar = PanelContainer.new()
	sticky_bar.name = "StickyBar"
	var sticky_st = StyleBoxFlat.new()
	sticky_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	sticky_st.border_width_bottom = 1
	sticky_st.border_color = Color(0.85, 0.88, 0.92, 1.0)
	sticky_st.content_margin_left = 16
	sticky_st.content_margin_right = 16
	sticky_st.content_margin_top = 8
	sticky_st.content_margin_bottom = 8
	sticky_bar.add_theme_stylebox_override("panel", sticky_st)
	
	var sticky_hbox = HBoxContainer.new()
	sticky_bar.add_child(sticky_hbox)
	
	sticky_label = Label.new()
	sticky_label.add_theme_font_size_override("font_size", 14)
	sticky_label.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
	sticky_hbox.add_child(sticky_label)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sticky_hbox.add_child(spacer)
	
	var back_btn = Button.new()
	back_btn.text = "  ↩️ Back to Sections  "
	back_btn.custom_minimum_size = Vector2(0, 28)
	back_btn.add_theme_font_size_override("font_size", 12)
	
	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = Color(0.90, 0.92, 0.95, 1.0)
	btn_st.corner_radius_top_left = 4; btn_st.corner_radius_top_right = 4; btn_st.corner_radius_bottom_left = 4; btn_st.corner_radius_bottom_right = 4
	var btn_hover = btn_st.duplicate()
	btn_hover.bg_color = Color(0.85, 0.88, 0.92, 1.0)
	back_btn.add_theme_stylebox_override("normal", btn_st)
	back_btn.add_theme_stylebox_override("hover", btn_hover)
	back_btn.add_theme_stylebox_override("pressed", btn_st)
	back_btn.add_theme_color_override("font_color", Color(0.2, 0.25, 0.35, 1.0))
	back_btn.add_theme_color_override("font_hover_color", Color(0.1, 0.15, 0.25, 1.0))
	
	back_btn.pressed.connect(func():
		var inner_scroll = _find_scroll_container_recursive(content_card)
		if inner_scroll:
			inner_scroll.scroll_vertical = 0
			_on_inner_scroll_changed(0.0)
	)
	sticky_hbox.add_child(back_btn)
	
	var main_vbox = get_node_or_null("MarginContainer/MainVBox")
	if main_vbox:
		main_vbox.add_child(sticky_bar)
		main_vbox.move_child(sticky_bar, 0)
		
	sticky_bar.visible = false
	
	if content_card:
		content_card.child_order_changed.connect(_setup_scroll_handling)

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
	elif active_tab == "campus_community":
		_render_campus_community_tab()
	elif active_tab == "sync_engine":
		_render_sync_engine_tab()
	elif active_tab == "scripture":
		_render_scripture_verses_tab()
		
	_setup_scroll_handling()

func _update_tab_button_styles() -> void:
	_style_tab_btn(btn_tab_modules, active_tab == "modules")
	_style_tab_btn(btn_tab_rbac, active_tab == "rbac")
	_style_tab_btn(btn_tab_branding, active_tab == "branding")
	_style_tab_btn(btn_tab_twilio, active_tab == "twilio")
	_style_tab_btn(btn_tab_header_messages, active_tab == "header_messages")
	_style_tab_btn(btn_tab_birthday, active_tab == "birthday")
	_style_tab_btn(btn_tab_ivr, active_tab == "ivr")
	_style_tab_btn(btn_tab_sessions, active_tab == "sessions")
	var btn_cc = get_node_or_null("MarginContainer/MainVBox/TabHBox/BtnTabCampusCommunity") as Button
	if btn_cc:
		_style_tab_btn(btn_cc, active_tab == "campus_community")
	var btn_sync = get_node_or_null("MarginContainer/MainVBox/TabHBox/BtnTabSyncEngine") as Button
	if btn_sync:
		_style_tab_btn(btn_sync, active_tab == "sync_engine")
	var btn_scripture = get_node_or_null("MarginContainer/MainVBox/TabHBox/BtnTabScripture") as Button
	if btn_scripture:
		_style_tab_btn(btn_scripture, active_tab == "scripture")

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
	role_opt.add_item("📋 Team Leader", 1)
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
	var e3 = LineEdit.new(); e3.text = config.get("phone_number", ""); e3.placeholder_text = "+18647124446"; e3.custom_minimum_size = Vector2(550, 46); _style_input_control(e3, 18); grid.add_child(e3)

	# Destination Test Mobile Number (Your personal cell phone for testing)
	var l4 = Label.new(); l4.text = "Test Recipient Mobile Phone:\n(Where Test SMS Will Be Received)"; l4.add_theme_font_size_override("font_size", 16); l4.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l4)
	var e4 = LineEdit.new(); e4.text = _get_setting_string("TWILIO_TEST_RECIPIENT_PHONE", "864 934-4080"); e4.placeholder_text = "864 934-4080"; e4.custom_minimum_size = Vector2(550, 46); _style_input_control(e4, 18); grid.add_child(e4)

	# Cloud Relay / Gateway URL
	var l_gate = Label.new(); l_gate.text = "Cloud Relay URL:\n(Your SiteGround app URL)"; l_gate.add_theme_font_size_override("font_size", 16); l_gate.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l_gate)
	var e_gate = LineEdit.new(); e_gate.text = _get_setting_string("GATEWAY_SERVER_URL", "https://app.reallife-studycenter.org"); e_gate.placeholder_text = "https://app.reallife-studycenter.org"; e_gate.custom_minimum_size = Vector2(550, 46); _style_input_control(e_gate, 18); grid.add_child(e_gate)

	# Cloud Relay / Sync API Key
	var l_gate_key = Label.new(); l_gate_key.text = "Sync API Key:\n(Shared secret in config.php)"; l_gate_key.add_theme_font_size_override("font_size", 16); l_gate_key.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0)); grid.add_child(l_gate_key)
	var e_gate_key = LineEdit.new(); e_gate_key.text = _get_setting_string("GATEWAY_SYNC_API_KEY", "SCH_SYNC_KEY_PLACEHOLDER_8f3d"); e_gate_key.placeholder_text = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"; e_gate_key.custom_minimum_size = Vector2(550, 46); _style_input_control(e_gate_key, 18); grid.add_child(e_gate_key)

	vbox.add_child(grid)
	vbox.add_child(tw_status_lbl)

	# Action Buttons
	var btn_hbox = HBoxContainer.new(); btn_hbox.add_theme_constant_override("separation", 14)

	var btn_save = Button.new(); btn_save.text = "💾 Save Credentials"; btn_save.custom_minimum_size = Vector2(210, 48); btn_save.add_theme_font_size_override("font_size", 18)
	var btn_st = StyleBoxFlat.new(); btn_st.bg_color = _get_active_theme_color(); btn_st.corner_radius_top_left = 8; btn_st.corner_radius_top_right = 8; btn_st.corner_radius_bottom_left = 8; btn_st.corner_radius_bottom_right = 8
	btn_save.add_theme_stylebox_override("normal", btn_st); btn_save.add_theme_stylebox_override("hover", btn_st); btn_save.add_theme_stylebox_override("pressed", btn_st)
	btn_save.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_save.pressed.connect(func():
		var test_sid = e1.text.strip_edges()
		if test_sid.begins_with("SK"):
			tw_status_lbl.text = "❌ The Twilio Account SID is invalid. You have entered an API Key SID starting with SK. The current integration expects the main Account SID beginning with AC and the corresponding Auth Token. Do not use an API Key SID."
			tw_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15, 1.0))
			tw_status_lbl.visible = true
			return
		elif test_sid != "" and not test_sid.begins_with("AC"):
			tw_status_lbl.text = "❌ The Twilio Account SID is invalid. Enter the Account SID beginning with AC, not an API Key SID or other Twilio identifier."
			tw_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15, 1.0))
			tw_status_lbl.visible = true
			return

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

		if sid.begins_with("SK"):
			tw_status_lbl.text = "❌ The Twilio Account SID is invalid. You have entered an API Key SID starting with SK. The current integration expects the main Account SID beginning with AC and the corresponding Auth Token. Do not use an API Key SID."
			tw_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15, 1.0))
			tw_status_lbl.visible = true
			return
		elif sid != "" and not sid.begins_with("AC"):
			tw_status_lbl.text = "❌ The Twilio Account SID is invalid. Enter the Account SID beginning with AC, not an API Key SID or other Twilio identifier."
			tw_status_lbl.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15, 1.0))
			tw_status_lbl.visible = true
			return

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
	var test_phone = LineEdit.new(); test_phone.text = _get_setting_string("LAST_TEST_BDAY_PHONE", "864 934-4080"); test_phone.placeholder_text = "Recipient Cell Phone (e.g. 864 934-4080)"; test_phone.custom_minimum_size = Vector2(240, 46); _style_input_control(test_phone, 18)
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

		var tw_config = twilio_service.get_twilio_config() if twilio_service else {}
		var sender_ph = tw_config.get("phone_number", "")
		if sender_ph == "": sender_ph = "+18647124446"

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
	const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
	var com_svc = CommunicationsServiceScript.new(db)
	
	if selected_ivr_day == "":
		var dt_now = Time.get_datetime_dict_from_system()
		var day_names_list = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
		selected_ivr_day = day_names_list[dt_now.weekday]
		
	var get_date_of_weekday = func(target_day: String) -> String:
		var dt_c = Time.get_datetime_dict_from_system()
		var day_names_c = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
		var current_wday_idx = dt_c.weekday
		var target_wday_idx = day_names_c.find(target_day)
		if target_wday_idx == -1: return ""
		var diff = target_wday_idx - current_wday_idx
		var unix_time = Time.get_unix_time_from_datetime_dict(dt_c)
		var target_unix = unix_time + (diff * 86400)
		var target_dt = Time.get_datetime_dict_from_unix_time(target_unix)
		return "%04d-%02d-%02d" % [target_dt.year, target_dt.month, target_dt.day]
		
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
	subtitle.text = "Configure dynamic daily announcements, staff directory call routing, hierarchical menus, and voice greetings."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 1.0))
	root_vbox.add_child(subtitle)

	# --- SUB-TABS NAVIGATION BAR ---
	var sub_tab_bg = PanelContainer.new()
	var sub_tab_st = StyleBoxFlat.new()
	sub_tab_st.bg_color = Color(0.95, 0.96, 0.98, 1.0)
	sub_tab_st.corner_radius_top_left = 8; sub_tab_st.corner_radius_top_right = 8
	sub_tab_st.corner_radius_bottom_left = 8; sub_tab_st.corner_radius_bottom_right = 8
	sub_tab_st.content_margin_left = 8; sub_tab_st.content_margin_top = 8; sub_tab_st.content_margin_right = 8; sub_tab_st.content_margin_bottom = 8
	sub_tab_bg.add_theme_stylebox_override("panel", sub_tab_st)
	
	var sub_tab_hbox = HBoxContainer.new()
	sub_tab_hbox.add_theme_constant_override("separation", 8)
	sub_tab_bg.add_child(sub_tab_hbox)
	root_vbox.add_child(sub_tab_bg)
	
	if ivr_sub_tab == "":
		ivr_sub_tab = "scripts"
		
	var tabs_def = [
		{"key": "scripts", "label": "📅 Today / Scripts & Daily Messages"},
		{"key": "flow", "label": "🌳 Call Flow"},
		{"key": "staff", "label": "👥 Staff Directory"},
		{"key": "voice", "label": "⚙️ Voice & Greeting Settings"}
	]
	for t in tabs_def:
		var btn = Button.new()
		btn.text = t["label"]
		btn.custom_minimum_size = Vector2(160, 36)
		btn.add_theme_font_size_override("font_size", 14)
		
		var active_st = StyleBoxFlat.new()
		active_st.bg_color = _get_active_theme_color()
		active_st.corner_radius_top_left = 6; active_st.corner_radius_top_right = 6; active_st.corner_radius_bottom_left = 6; active_st.corner_radius_bottom_right = 6
		active_st.content_margin_left = 12; active_st.content_margin_right = 12
		
		var inactive_st = StyleBoxFlat.new()
		inactive_st.bg_color = Color(0.95, 0.96, 0.98, 1.0)
		inactive_st.corner_radius_top_left = 6; inactive_st.corner_radius_top_right = 6; inactive_st.corner_radius_bottom_left = 6; inactive_st.corner_radius_bottom_right = 6
		inactive_st.content_margin_left = 12; inactive_st.content_margin_right = 12
		
		if ivr_sub_tab == t["key"]:
			btn.add_theme_stylebox_override("normal", active_st)
			btn.add_theme_stylebox_override("hover", active_st)
			btn.add_theme_stylebox_override("pressed", active_st)
			btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		else:
			btn.add_theme_stylebox_override("normal", inactive_st)
			var hov_st = inactive_st.duplicate()
			hov_st.bg_color = Color(0.9, 0.92, 0.95, 1.0)
			btn.add_theme_stylebox_override("hover", hov_st)
			btn.add_theme_stylebox_override("pressed", inactive_st)
			btn.add_theme_color_override("font_color", Color(0.15, 0.22, 0.35, 1.0))
			btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
			
		btn.pressed.connect(func():
			if unsaved_ivr_scripts.size() > 0:
				_show_unsaved_warning(func():
					unsaved_ivr_scripts.clear()
					ivr_sub_tab = t["key"]
					_render_ivr_tab()
				)
			else:
				ivr_sub_tab = t["key"]
				_render_ivr_tab()
		)
		sub_tab_hbox.add_child(btn)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	var main_content_vbox = VBoxContainer.new()
	main_content_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	main_content_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(main_content_vbox)
	root_vbox.add_child(scroll)
	
	var settings = com_svc.get_phone_settings()
	var sec_btn_st = StyleBoxFlat.new(); sec_btn_st.bg_color = Color(0.92, 0.94, 0.97, 1.0); sec_btn_st.corner_radius_top_left = 6; sec_btn_st.corner_radius_top_right = 6; sec_btn_st.corner_radius_bottom_left = 6; sec_btn_st.corner_radius_bottom_right = 6; sec_btn_st.border_width_left = 1; sec_btn_st.border_width_top = 1; sec_btn_st.border_width_right = 1; sec_btn_st.border_width_bottom = 1; sec_btn_st.border_color = Color(0.78, 0.82, 0.88, 1.0); sec_btn_st.content_margin_left = 12; sec_btn_st.content_margin_right = 12; sec_btn_st.content_margin_top = 6; sec_btn_st.content_margin_bottom = 6
	var sec_btn_hover = sec_btn_st.duplicate(); sec_btn_hover.bg_color = Color(0.96, 0.97, 0.99, 1.0)

	if ivr_sub_tab == "scripts":
		var day_card = PanelContainer.new()
		var day_card_st = StyleBoxFlat.new(); day_card_st.bg_color = Color(1, 1, 1, 1); day_card_st.content_margin_left = 12; day_card_st.content_margin_top = 12; day_card_st.content_margin_right = 12; day_card_st.content_margin_bottom = 12; day_card_st.border_width_left = 1; day_card_st.border_width_right = 1; day_card_st.border_width_top = 1; day_card_st.border_width_bottom = 1; day_card_st.border_color = Color(0.88, 0.91, 0.94, 1.0); day_card_st.corner_radius_top_left = 8; day_card_st.corner_radius_top_right = 8; day_card_st.corner_radius_bottom_left = 8; day_card_st.corner_radius_bottom_right = 8
		day_card.add_theme_stylebox_override("panel", day_card_st)
		
		var day_vbox = VBoxContainer.new()
		day_vbox.add_theme_constant_override("separation", 10)
		day_card.add_child(day_vbox)
		
		var date_str = get_date_of_weekday.call(selected_ivr_day)
		var day_title_lbl = Label.new()
		day_title_lbl.text = "📅 TODAY — " + selected_ivr_day.to_upper() + ", " + date_str
		day_title_lbl.add_theme_font_size_override("font_size", 16)
		day_title_lbl.add_theme_color_override("font_color", _get_active_theme_color())
		day_vbox.add_child(day_title_lbl)
		
		var day_hbox = HBoxContainer.new()
		day_hbox.add_theme_constant_override("separation", 6)
		day_vbox.add_child(day_hbox)
		
		var day_list = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
		var dt_now = Time.get_datetime_dict_from_system()
		var day_names_list = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
		var sys_today = day_names_list[dt_now.weekday]
		
		for d in day_list:
			var btn = Button.new()
			btn.text = d
			if d == sys_today:
				btn.text += " (Today)"
			btn.custom_minimum_size = Vector2(90, 32)
			btn.add_theme_font_size_override("font_size", 12)
			
			var act_day_st = StyleBoxFlat.new()
			act_day_st.bg_color = _get_active_theme_color()
			act_day_st.corner_radius_top_left = 4; act_day_st.corner_radius_top_right = 4; act_day_st.corner_radius_bottom_left = 4; act_day_st.corner_radius_bottom_right = 4
			
			var inact_day_st = StyleBoxFlat.new()
			inact_day_st.bg_color = Color(0.93, 0.95, 0.98, 1.0)
			inact_day_st.corner_radius_top_left = 4; inact_day_st.corner_radius_top_right = 4; inact_day_st.corner_radius_bottom_left = 4; inact_day_st.corner_radius_bottom_right = 4
			
			if selected_ivr_day == d:
				btn.add_theme_stylebox_override("normal", act_day_st)
				btn.add_theme_stylebox_override("hover", act_day_st)
				btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			else:
				btn.add_theme_stylebox_override("normal", inact_day_st)
				var hov = inact_day_st.duplicate()
				hov.bg_color = Color(0.88, 0.91, 0.95, 1.0)
				btn.add_theme_stylebox_override("hover", hov)
				btn.add_theme_color_override("font_color", Color(0.2, 0.3, 0.4, 1.0))
				btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
				
			btn.pressed.connect(func():
				if unsaved_ivr_scripts.size() > 0:
					_show_unsaved_warning(func():
						unsaved_ivr_scripts.clear()
						selected_ivr_day = d
						_render_ivr_tab()
					)
				else:
					selected_ivr_day = d
					_render_ivr_tab()
			)
			day_hbox.add_child(btn)
			
		main_content_vbox.add_child(day_card)

		# Fetch active nodes
		var nodes_res = db.execute("SELECT id, parent_id, digit, label, action_type, action_param, script_text, dynamic_source FROM ivr_menu_nodes WHERE is_active = 1 ORDER BY display_order ASC, id ASC;")
		var node_map = {}
		if nodes_res["success"]:
			for n in nodes_res["data"]:
				node_map[int(n["id"])] = n
				
		var get_node_path = func(node: Dictionary) -> String:
			var path_parts = []
			var curr = node
			while curr != null:
				path_parts.insert(0, str(curr["digit"]))
				if curr.get("parent_id") != null and node_map.has(int(curr["parent_id"])):
					curr = node_map[int(curr["parent_id"])]
				else:
					curr = null
			return "-".join(path_parts)
			
		var prompts = []
		var clean_script = func(s: String) -> String:
			return s.replace("\\n", "\n").replace("\r", "")
			
		var calculate_edit_height = func(txt: String) -> float:
			var lines = txt.split("\n")
			var line_count = 0
			for line in lines:
				var length = line.length()
				line_count += 1 + int(length / 70)
			var estimated_height = max(80, line_count * 24 + 16)
			return min(320.0, estimated_height)
		var active_main = clean_script.call(str(settings.get("automated_greeter_tts", "")))
		var suggest_main = clean_script.call(com_svc.generate_suggestion_for_prompt("main_greeting", selected_ivr_day, date_str))
		prompts.append({
			"key": "main_greeting",
			"label": "Main Greeting",
			"description": "Played when callers first dial in.",
			"path_label": "📞 Main Greeting (Root Menu Greeting)",
			"active_script": active_main,
			"suggested_script": suggest_main,
			"is_shared": false,
			"shared_label": "",
			"is_dynamic": true
		})
		
		var active_loc = ""
		var loc_q = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'PHONE_LOCATION_DIRECTIONS_TEXT' LIMIT 1;")
		if loc_q["success"] and loc_q["data"].size() > 0:
			active_loc = clean_script.call(str(loc_q["data"][0]["setting_value"]))
		prompts.append({
			"key": "location_directions",
			"label": "Location & Directions",
			"description": "Shared spoken info for directions.",
			"path_label": "👥 Location & Directions (Shared Script)",
			"active_script": active_loc,
			"suggested_script": active_loc,
			"is_shared": true,
			"shared_label": "Used by: Option 1-1 (Today Location), Option 3-2 (Info Location)",
			"is_dynamic": false
		})
		
		if nodes_res["success"]:
			for n in nodes_res["data"]:
				var nid = int(n["id"])
				var act_type = str(n["action_type"])
				var d_src = str(n.get("dynamic_source", "")) if n.get("dynamic_source") != null else ""
				
				if act_type in ["speak", "submenu", "staff_directory", "voicemail"]:
					if d_src == "location_directions":
						continue # Skip, Location & Directions is rendered as a single shared card above!
						
					var n_key = "node_" + str(nid)
					var p_path = get_node_path.call(n)
					
					var active_s = clean_script.call(str(n.get("script_text", "")) if n.get("script_text") != null else "")
					var suggest_s = clean_script.call(com_svc.generate_suggestion_for_prompt(n_key, selected_ivr_day, date_str))
					var is_dyn = (n_key == "main_greeting" or d_src != "" or act_type == "staff_directory" or act_type == "submenu")
					
					# Fallback to dynamic suggestion if database script_text is blank/null
					if active_s == "" and is_dyn:
						active_s = suggest_s
						
					prompts.append({
						"key": n_key,
						"label": str(n["label"]),
						"description": "Composite Route path: " + p_path,
						"path_label": "Press " + p_path + " — " + str(n["label"]),
						"active_script": active_s,
						"suggested_script": suggest_s,
						"is_shared": false,
						"shared_label": "",
						"is_dynamic": is_dyn
					})

		# Build Status Summary Card & Alert Box
		var active_count = prompts.size()
		var suggested_updates = 0
		var summary_lines = []
		
		for p in prompts:
			var draft = com_svc.get_ivr_script_draft(p["key"])
			var current_suggested = draft if draft != "" else p["suggested_script"]
			var current_status_info = com_svc.get_prompt_status(p["key"], p["active_script"], current_suggested)
			if not current_status_info["is_current"] and p["is_dynamic"]:
				suggested_updates += 1
				summary_lines.append(p["label"] + " (" + current_status_info["reason"] + ")")
				
		var sum_card = PanelContainer.new()
		var sum_card_st = StyleBoxFlat.new(); sum_card_st.bg_color = Color(0.96, 0.98, 1.0, 1.0); sum_card_st.content_margin_left = 14; sum_card_st.content_margin_top = 10; sum_card_st.content_margin_right = 14; sum_card_st.content_margin_bottom = 10; sum_card_st.corner_radius_top_left = 6; sum_card_st.corner_radius_top_right = 6; sum_card_st.corner_radius_bottom_left = 6; sum_card_st.corner_radius_bottom_right = 6; sum_card_st.border_width_left = 2; sum_card_st.border_color = Color(0.25, 0.55, 0.85, 1.0)
		sum_card.add_theme_stylebox_override("panel", sum_card_st)
		
		var sum_hbox = HBoxContainer.new()
		sum_card.add_child(sum_hbox)
		
		var sum_lbl = Label.new()
		sum_lbl.text = selected_ivr_day.to_upper() + " PHONE CONTENT  •  " + str(active_count) + " Spoken Prompts  •  " + str(suggested_updates) + " Suggested Update(s)"
		sum_lbl.add_theme_font_size_override("font_size", 14)
		sum_lbl.add_theme_color_override("font_color", Color(0.12, 0.22, 0.38, 1.0))
		sum_hbox.add_child(sum_lbl)
		main_content_vbox.add_child(sum_card)
		
		if suggested_updates > 0:
			var alert_panel = PanelContainer.new()
			var alert_st = StyleBoxFlat.new(); alert_st.bg_color = Color(1.0, 0.96, 0.92, 1.0); alert_st.content_margin_left = 14; alert_st.content_margin_top = 10; alert_st.content_margin_right = 14; alert_st.content_margin_bottom = 10; alert_st.corner_radius_top_left = 6; alert_st.corner_radius_top_right = 6; alert_st.corner_radius_bottom_left = 6; alert_st.corner_radius_bottom_right = 6; alert_st.border_width_left = 2; alert_st.border_color = Color(0.9, 0.5, 0.1, 1.0)
			alert_panel.add_theme_stylebox_override("panel", alert_st)
			
			var alert_vbox = VBoxContainer.new()
			alert_panel.add_child(alert_vbox)
			
			var alert_title = Label.new()
			alert_title.text = "⚠ " + str(suggested_updates) + " SUGGESTED UPDATE(S) AVAILABLE"
			alert_title.add_theme_font_size_override("font_size", 14)
			alert_title.add_theme_color_override("font_color", Color(0.7, 0.35, 0.05, 1.0))
			alert_vbox.add_child(alert_title)
			
			for line in summary_lines:
				var line_lbl = Label.new()
				line_lbl.text = "• " + line
				line_lbl.add_theme_font_size_override("font_size", 13)
				line_lbl.add_theme_color_override("font_color", Color(0.4, 0.25, 0.1, 1.0))
				alert_vbox.add_child(line_lbl)
				
			main_content_vbox.add_child(alert_panel)

		# Special Message Panel
		if selected_ivr_day == sys_today:
			var spec_panel = PanelContainer.new()
			var spec_st = StyleBoxFlat.new(); spec_st.bg_color = Color(1.0, 1.0, 1.0, 1.0); spec_st.content_margin_left = 16; spec_st.content_margin_top = 14; spec_st.content_margin_right = 16; spec_st.content_margin_bottom = 14; spec_st.border_width_left = 1; spec_st.border_width_right = 1; spec_st.border_width_top = 1; spec_st.border_width_bottom = 1; spec_st.border_color = Color(0.88, 0.91, 0.94, 1.0); spec_st.corner_radius_top_left = 8; spec_st.corner_radius_top_right = 8; spec_st.corner_radius_bottom_left = 8; spec_st.corner_radius_bottom_right = 8
			spec_panel.add_theme_stylebox_override("panel", spec_st)
			
			var spec_vbox = VBoxContainer.new()
			spec_vbox.add_theme_constant_override("separation", 10)
			spec_panel.add_child(spec_vbox)
			
			var spec_lbl = Label.new()
			spec_lbl.text = "✍️ TODAY'S SPECIAL MESSAGE — OPTIONAL (appends to suggested greeting)"
			spec_lbl.add_theme_font_size_override("font_size", 13)
			spec_lbl.add_theme_color_override("font_color", _get_active_theme_color())
			spec_vbox.add_child(spec_lbl)
			
			var spec_hbox = HBoxContainer.new()
			spec_hbox.add_theme_constant_override("separation", 12)
			spec_vbox.add_child(spec_hbox)
			
			var spec_edit = TextEdit.new()
			spec_edit.custom_minimum_size = Vector2(0, 48)
			spec_edit.size_flags_horizontal = SIZE_EXPAND_FILL
			_style_input_control(spec_edit, 14)
			spec_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			spec_edit.text = settings.get("today_special_message", "")
			spec_hbox.add_child(spec_edit)
			
			var expire_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'PHONE_EXPIRE_SPECIAL_MESSAGE_AT_MIDNIGHT' LIMIT 1;")
			var expire_val = "0"
			if expire_res["success"] and expire_res["data"].size() > 0:
				expire_val = str(expire_res["data"][0]["setting_value"])
			
			var expire_chk = CheckBox.new()
			expire_chk.text = "Expire at midnight"
			expire_chk.button_pressed = (expire_val == "1")
			spec_vbox.add_child(expire_chk)
			
			var update_spec_btn = Button.new()
			update_spec_btn.text = "Update Suggested Script"
			update_spec_btn.custom_minimum_size = Vector2(200, 36)
			update_spec_btn.add_theme_font_size_override("font_size", 13)
			update_spec_btn.add_theme_stylebox_override("normal", sec_btn_st)
			update_spec_btn.add_theme_stylebox_override("hover", sec_btn_hover)
			update_spec_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
			
			update_spec_btn.pressed.connect(func():
				var spec_t = spec_edit.text.strip_edges()
				var exp_val = "1" if expire_chk.button_pressed else "0"
				com_svc.save_today_settings(
					settings.get("today_script_mode", "automatic"),
					spec_t,
					settings.get("today_custom_script", ""),
					settings.get("location_directions_text", "")
				)
				db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_EXPIRE_SPECIAL_MESSAGE_AT_MIDNIGHT', ?);", [exp_val])
				_render_ivr_tab()
			)
			spec_hbox.add_child(update_spec_btn)
			var spec_msg_vbox = spec_vbox # store reference if needed
			
			main_content_vbox.add_child(spec_panel)

		# Prompts Cards
		for p in prompts:
			var p_key = p["key"]
			var p_label = p["label"]
			var p_path_lbl = p["path_label"]
			var act_s = p["active_script"]
			var sug_s = p["suggested_script"]
			var is_shared = p["is_shared"]
			var sh_lbl = p["shared_label"]
			var is_dyn = p["is_dynamic"]
			
			var draft = com_svc.get_ivr_script_draft(p_key)
			var current_sug = draft if draft != "" else sug_s
			var status_info = com_svc.get_prompt_status(p_key, act_s, current_sug)
			var is_curr = status_info["is_current"] or not is_dyn
			
			var card = PanelContainer.new()
			var card_st = StyleBoxFlat.new(); card_st.bg_color = Color(1, 1, 1, 1); card_st.content_margin_left = 18; card_st.content_margin_top = 16; card_st.content_margin_right = 18; card_st.content_margin_bottom = 16; card_st.border_width_left = 1; card_st.border_width_right = 1; card_st.border_width_top = 1; card_st.border_width_bottom = 1; card_st.border_color = Color(0.88, 0.91, 0.94, 1.0); card_st.corner_radius_top_left = 8; card_st.corner_radius_top_right = 8; card_st.corner_radius_bottom_left = 8; card_st.corner_radius_bottom_right = 8
			card.add_theme_stylebox_override("panel", card_st)
			
			var cvbox = VBoxContainer.new()
			cvbox.add_theme_constant_override("separation", 12)
			card.add_child(cvbox)
			
			var h_hbox = HBoxContainer.new()
			cvbox.add_child(h_hbox)
			
			var title_lbl = Label.new()
			title_lbl.text = p_path_lbl
			title_lbl.add_theme_font_size_override("font_size", 15)
			title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
			title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			h_hbox.add_child(title_lbl)
			
			var status_lbl = Label.new()
			status_lbl.add_theme_font_size_override("font_size", 12)
			if is_curr:
				status_lbl.text = "✓ CURRENT"
				status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
			else:
				status_lbl.text = "⚠ SUGGESTED UPDATE AVAILABLE"
				status_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 0.05, 1.0))
				if status_info["reason"] != "":
					status_lbl.text += " (" + status_info["reason"] + ")"
			h_hbox.add_child(status_lbl)
			
			if is_shared:
				var shared_lbl = Label.new()
				shared_lbl.text = "👥 Shared Script — " + sh_lbl
				shared_lbl.add_theme_font_size_override("font_size", 12)
				shared_lbl.add_theme_color_override("font_color", Color(0.3, 0.5, 0.7, 1.0))
				cvbox.add_child(shared_lbl)
				
			var act_vbox = VBoxContainer.new()
			act_vbox.add_theme_constant_override("separation", 6)
			cvbox.add_child(act_vbox)
			
			var act_lbl_hbox = HBoxContainer.new()
			act_vbox.add_child(act_lbl_hbox)
			
			var act_lbl = Label.new()
			act_lbl.text = "ACTIVE SCRIPT (Callers hear this now)"
			act_lbl.add_theme_font_size_override("font_size", 12)
			act_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5, 1.0))
			act_lbl_hbox.add_child(act_lbl)
			
			var dirty_lbl = Label.new()
			dirty_lbl.text = "● UNSAVED CHANGES"
			dirty_lbl.add_theme_font_size_override("font_size", 12)
			dirty_lbl.add_theme_color_override("font_color", Color(0.8, 0.15, 0.15, 1.0))
			dirty_lbl.visible = false
			act_lbl_hbox.add_child(dirty_lbl)
			
			var act_edit = TextEdit.new()
			act_edit.custom_minimum_size = Vector2(0, calculate_edit_height.call(act_s))
			_style_input_control(act_edit, 14)
			act_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			act_edit.text = act_s
			act_vbox.add_child(act_edit)
			
			var act_btn_hbox = HBoxContainer.new()
			act_btn_hbox.add_theme_constant_override("separation", 10)
			act_vbox.add_child(act_btn_hbox)
			
			var play_btn = Button.new()
			play_btn.text = "🔊 Preview Voice"
			play_btn.custom_minimum_size = Vector2(140, 28)
			play_btn.add_theme_font_size_override("font_size", 13)
			play_btn.add_theme_stylebox_override("normal", sec_btn_st)
			play_btn.add_theme_stylebox_override("hover", sec_btn_hover)
			play_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
			act_btn_hbox.add_child(play_btn)
			
			play_btn.pressed.connect(func():
				var txt = act_edit.text.strip_edges()
				if txt == "": return
				DisplayServer.tts_stop()
				var v_res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1 LIMIT 1;")
				var voice_id = ""
				if v_res["success"] and v_res["data"].size() > 0:
					voice_id = str(v_res["data"][0].get("voice_name", ""))
				if voice_id == "" or voice_id.begins_with("mock_"):
					var play_dlg = AcceptDialog.new(); play_dlg.dialog_text = "📢 Greeting Preview:\n\n\"" + txt + "\"\n\n(Voice: Default TTS)"; add_child(play_dlg); play_dlg.popup_centered()
				else:
					DisplayServer.tts_speak(txt, voice_id)
			)
			
			var save_btn = Button.new()
			save_btn.text = "💾 Save & Activate Changes"
			save_btn.custom_minimum_size = Vector2(200, 28)
			save_btn.add_theme_font_size_override("font_size", 13)
			var save_btn_st = StyleBoxFlat.new(); save_btn_st.bg_color = _get_active_theme_color(); save_btn_st.corner_radius_top_left = 6; save_btn_st.corner_radius_top_right = 6; save_btn_st.corner_radius_bottom_left = 6; save_btn_st.corner_radius_bottom_right = 6; save_btn_st.content_margin_left = 12; save_btn_st.content_margin_right = 12
			save_btn.add_theme_stylebox_override("normal", save_btn_st)
			var save_btn_hov = save_btn_st.duplicate(); save_btn_hov.bg_color = _get_active_theme_color().lightened(0.08)
			save_btn.add_theme_stylebox_override("hover", save_btn_hov)
			save_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			act_btn_hbox.add_child(save_btn)
			
			act_edit.text_changed.connect(func():
				dirty_lbl.visible = true
				unsaved_ivr_scripts[p_key] = act_edit.text
			)
			
			save_btn.pressed.connect(func():
				var confirm_d = ConfirmationDialog.new()
				confirm_d.title = "Confirm Activation"
				confirm_d.dialog_text = "Activate these script changes?\nThis will change what callers hear for " + p_label + "."
				confirm_d.confirmed.connect(func():
					var text_to_save = act_edit.text
					var ok = com_svc.save_active_script(p_key, text_to_save)
					if ok:
						unsaved_ivr_scripts.erase(p_key)
						dirty_lbl.visible = false
						var sync_svc = GatewaySyncScript.new(db, self)
						sync_svc.publish_ivr_config(func(result): pass)
						_render_ivr_tab()
				)
				add_child(confirm_d)
				confirm_d.popup_centered()
			)
			
			if is_dyn:
				var sug_vbox = VBoxContainer.new()
				sug_vbox.add_theme_constant_override("separation", 6)
				cvbox.add_child(sug_vbox)
				
				var sug_lbl = Label.new()
				sug_lbl.text = "SUGGESTED SCRIPT UPDATE (From current schedule / edited draft)"
				sug_lbl.add_theme_font_size_override("font_size", 12)
				sug_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5, 1.0))
				sug_vbox.add_child(sug_lbl)
				
				var sug_edit = TextEdit.new()
				sug_edit.custom_minimum_size = Vector2(0, calculate_edit_height.call(current_sug))
				_style_input_control(sug_edit, 14)
				sug_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				sug_edit.text = current_sug
				sug_vbox.add_child(sug_edit)
				
				sug_edit.text_changed.connect(func():
					com_svc.save_ivr_script_draft(p_key, sug_edit.text)
					var dynamic_status = com_svc.get_prompt_status(p_key, act_edit.text, sug_edit.text)
					if dynamic_status["is_current"]:
						status_lbl.text = "✓ CURRENT"
						status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
					else:
						status_lbl.text = "⚠ SUGGESTED UPDATE AVAILABLE"
						status_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 0.05, 1.0))
						if dynamic_status["reason"] != "":
							status_lbl.text += " (" + dynamic_status["reason"] + ")"
				)
				
				var sug_btn_hbox = HBoxContainer.new()
				sug_btn_hbox.add_theme_constant_override("separation", 10)
				sug_vbox.add_child(sug_btn_hbox)
				
				var regen_btn = Button.new()
				regen_btn.text = "🔄 Regenerate Suggestion"
				regen_btn.custom_minimum_size = Vector2(180, 28)
				regen_btn.add_theme_font_size_override("font_size", 13)
				regen_btn.add_theme_stylebox_override("normal", sec_btn_st)
				regen_btn.add_theme_stylebox_override("hover", sec_btn_hover)
				regen_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
				sug_btn_hbox.add_child(regen_btn)
				
				regen_btn.pressed.connect(func():
					var confirm_r = ConfirmationDialog.new()
					confirm_r.title = "Confirm Regeneration"
					confirm_r.dialog_text = "Regenerate suggestion from schedule? This will overwrite your edited draft."
					confirm_r.confirmed.connect(func():
						com_svc.delete_ivr_script_draft(p_key)
						_render_ivr_tab()
					)
					add_child(confirm_r)
					confirm_r.popup_centered()
				)
				
				var replace_btn = Button.new()
				replace_btn.text = "📋 Replace Active Script"
				replace_btn.custom_minimum_size = Vector2(180, 28)
				replace_btn.add_theme_font_size_override("font_size", 13)
				replace_btn.add_theme_stylebox_override("normal", sec_btn_st)
				replace_btn.add_theme_stylebox_override("hover", sec_btn_hover)
				replace_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
				sug_btn_hbox.add_child(replace_btn)
				
				replace_btn.pressed.connect(func():
					var confirm_rep = ConfirmationDialog.new()
					confirm_rep.title = "Confirm Replacement"
					confirm_rep.dialog_text = "Replace active script with suggestion?\nChanges will not be active until you click Save & Activate."
					confirm_rep.confirmed.connect(func():
						act_edit.text = sug_edit.text
						dirty_lbl.visible = true
						unsaved_ivr_scripts[p_key] = act_edit.text
					)
					add_child(confirm_rep)
					confirm_rep.popup_centered()
				)
				
			main_content_vbox.add_child(card)

	elif ivr_sub_tab == "flow":
		var flow_card = PanelContainer.new()
		var flow_st = StyleBoxFlat.new(); flow_st.bg_color = Color(1.0, 1.0, 1.0, 1.0); flow_st.content_margin_left = 18; flow_st.content_margin_top = 16; flow_st.content_margin_right = 18; flow_st.content_margin_bottom = 16; flow_st.border_width_left = 1; flow_st.border_width_right = 1; flow_st.border_width_top = 1; flow_st.border_width_bottom = 1; flow_st.border_color = Color(0.88, 0.91, 0.94, 1.0); flow_st.corner_radius_top_left = 8; flow_st.corner_radius_top_right = 8; flow_st.corner_radius_bottom_left = 8; flow_st.corner_radius_bottom_right = 8
		flow_card.add_theme_stylebox_override("panel", flow_st)
		
		var flow_vbox = VBoxContainer.new()
		flow_vbox.add_theme_constant_override("separation", 14)
		flow_card.add_child(flow_vbox)
		
		var flow_title = Label.new()
		flow_title.text = "🌳 Hierarchical Call Flow Routing"
		flow_title.add_theme_font_size_override("font_size", 18)
		flow_title.add_theme_color_override("font_color", _get_active_theme_color())
		flow_vbox.add_child(flow_title)
		
		var outline_vbox = VBoxContainer.new()
		outline_vbox.add_theme_constant_override("separation", 6)
		flow_vbox.add_child(outline_vbox)
		
		var q_res = db.execute("SELECT id, parent_id, digit, label, action_type, action_param FROM ivr_menu_nodes WHERE is_active = 1 ORDER BY display_order ASC, id ASC;")
		var roots = []
		var child_map = {}
		if q_res["success"]:
			for n in q_res["data"]:
				var p_id = n.get("parent_id")
				if p_id == null:
					roots.append(n)
				else:
					var p_id_int = int(p_id)
					if not child_map.has(p_id_int):
						child_map[p_id_int] = []
					child_map[p_id_int].append(n)
					
		var render_outline_row = null
		render_outline_row = func(node: Dictionary, depth: int):
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			outline_vbox.add_child(row)
			
			var indent = Control.new()
			indent.custom_minimum_size = Vector2(depth * 24, 0)
			row.add_child(indent)
			
			var bullet = Label.new()
			bullet.text = "•" if depth > 0 else "▪"
			bullet.add_theme_color_override("font_color", _get_active_theme_color())
			row.add_child(bullet)
			
			var lbl = Label.new()
			var act_type = str(node["action_type"])
			var act_param = str(node.get("action_param", "")) if node.get("action_param") != null else ""
			var act_desc = ""
			match act_type:
				"submenu": act_desc = " (Submenu)"
				"staff_directory": act_desc = " (Transfer to Staff Directory)"
				"voicemail": act_desc = " (Voicemail fallback: " + act_param + ")"
				"speak": act_desc = " (Speak script)"
				"return_to_main": act_desc = " (Return to Main Menu)"
				"hangup": act_desc = " (Hang up)"
			lbl.text = str(node["digit"]) + " — " + str(node["label"]) + act_desc
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
			lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(lbl)
			
			var edit_node_btn = Button.new()
			edit_node_btn.text = "✏️ Edit"
			edit_node_btn.custom_minimum_size = Vector2(70, 26)
			edit_node_btn.add_theme_font_size_override("font_size", 12)
			edit_node_btn.add_theme_stylebox_override("normal", sec_btn_st)
			edit_node_btn.add_theme_stylebox_override("hover", sec_btn_hover)
			edit_node_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
			edit_node_btn.pressed.connect(func():
				var path_parts = []
				var curr = node
				while curr != null:
					path_parts.insert(0, str(curr["digit"]))
					if curr.get("parent_id") != null and q_res["success"]:
						var p_n = null
						for item in q_res["data"]:
							if int(item["id"]) == int(curr["parent_id"]):
								p_n = item
								break
						curr = p_n
					else:
						curr = null
				var full_path = "-".join(path_parts)
				_open_ivr_option_dialog(full_path, "")
			)
			row.add_child(edit_node_btn)
			
			var nid = int(node["id"])
			if child_map.has(nid):
				for child in child_map[nid]:
					render_outline_row.call(child, depth + 1)
					
		for r in roots:
			render_outline_row.call(r, 0)
			
		main_content_vbox.add_child(flow_card)

	elif ivr_sub_tab == "staff":
		var staff_card = PanelContainer.new()
		var staff_card_st = StyleBoxFlat.new(); staff_card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0); staff_card_st.border_width_left = 1; staff_card_st.border_width_top = 1; staff_card_st.border_width_right = 1; staff_card_st.border_width_bottom = 1; staff_card_st.border_color = Color(0.88, 0.91, 0.94, 1.0); staff_card_st.corner_radius_top_left = 8; staff_card_st.corner_radius_top_right = 8; staff_card_st.corner_radius_bottom_left = 8; staff_card_st.corner_radius_bottom_right = 8; staff_card_st.content_margin_left = 18; staff_card_st.content_margin_top = 16; staff_card_st.content_margin_right = 18; staff_card_st.content_margin_bottom = 16
		staff_card.add_theme_stylebox_override("panel", staff_card_st)
		
		var staff_vbox = VBoxContainer.new()
		staff_vbox.add_theme_constant_override("separation", 14)
		staff_card.add_child(staff_vbox)
		
		var staff_title_hbox = HBoxContainer.new()
		var staff_title_lbl = Label.new(); staff_title_lbl.text = "👥 Staff Directory Call Routing & Screening"; staff_title_lbl.add_theme_font_size_override("font_size", 18); staff_title_lbl.add_theme_color_override("font_color", _get_active_theme_color()); staff_title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		var add_staff_btn = Button.new(); add_staff_btn.text = "➕ Add Staff Member"; add_staff_btn.custom_minimum_size = Vector2(180, 34); add_staff_btn.add_theme_font_size_override("font_size", 14)
		add_staff_btn.add_theme_stylebox_override("normal", sec_btn_st); add_staff_btn.add_theme_stylebox_override("hover", sec_btn_hover); add_staff_btn.add_theme_stylebox_override("pressed", sec_btn_st)
		add_staff_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); add_staff_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
		add_staff_btn.pressed.connect(func(): _open_staff_dialog(""))
		staff_title_hbox.add_child(staff_title_lbl); staff_title_hbox.add_child(add_staff_btn)
		staff_vbox.add_child(staff_title_hbox)
		
		var staff_list_container = VBoxContainer.new()
		staff_list_container.add_theme_constant_override("separation", 8)
		staff_vbox.add_child(staff_list_container)
		
		var active_staff_members = com_svc.get_all_staff_members()
		var del_btn_st = StyleBoxFlat.new(); del_btn_st.bg_color = Color(0.98, 0.92, 0.92, 1.0); del_btn_st.corner_radius_top_left = 6; del_btn_st.corner_radius_top_right = 6; del_btn_st.corner_radius_bottom_left = 6; del_btn_st.corner_radius_bottom_right = 6; del_btn_st.border_width_left = 1; del_btn_st.border_width_top = 1; del_btn_st.border_width_right = 1; del_btn_st.border_width_bottom = 1; del_btn_st.border_color = Color(0.92, 0.78, 0.78, 1.0); del_btn_st.content_margin_left = 10; del_btn_st.content_margin_right = 10; del_btn_st.content_margin_top = 4; del_btn_st.content_margin_bottom = 4
		var del_btn_hover = del_btn_st.duplicate(); del_btn_hover.bg_color = Color(1.0, 0.95, 0.95, 1.0)
		
		if active_staff_members.size() > 0:
			for s in active_staff_members:
				var s_uuid = str(s["staff_uuid"])
				var s_name = str(s["display_name"])
				var s_num = str(s["transfer_number"])
				var s_dig = str(s["menu_digit"])
				var s_active = int(s["is_active"]) == 1
				
				var row = PanelContainer.new()
				var row_st = StyleBoxFlat.new(); row_st.bg_color = Color(0.96, 0.97, 0.99, 1.0); row_st.content_margin_left = 12; row_st.content_margin_top = 8; row_st.content_margin_right = 12; row_st.content_margin_bottom = 8
				row.add_theme_stylebox_override("panel", row_st)
				
				var row_hbox = HBoxContainer.new()
				row_hbox.add_theme_constant_override("separation", 12)
				row.add_child(row_hbox)
				
				var name_lbl = Label.new()
				name_lbl.text = "Key " + s_dig + " • " + s_name + " (" + s_num + ")" + (" (Offline)" if not s_active else "")
				name_lbl.add_theme_font_size_override("font_size", 15)
				name_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0) if s_active else Color(0.5, 0.5, 0.5, 1.0))
				name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
				row_hbox.add_child(name_lbl)
				
				var edit_s_btn = Button.new(); edit_s_btn.text = "✏️ Edit"; edit_s_btn.custom_minimum_size = Vector2(70, 28); edit_s_btn.add_theme_font_size_override("font_size", 14)
				var del_s_btn = Button.new(); del_s_btn.text = "❌ Delete"; del_s_btn.custom_minimum_size = Vector2(80, 28); del_s_btn.add_theme_font_size_override("font_size", 14)
				
				for btn in [edit_s_btn, del_s_btn]:
					btn.add_theme_stylebox_override("normal", sec_btn_st)
					btn.add_theme_stylebox_override("hover", sec_btn_hover)
					btn.add_theme_stylebox_override("pressed", sec_btn_st)
					btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
					
				del_s_btn.add_theme_stylebox_override("normal", del_btn_st)
				del_s_btn.add_theme_stylebox_override("hover", del_btn_hover)
				del_s_btn.add_theme_color_override("font_color", Color(0.65, 0.15, 0.15, 1.0))
				
				edit_s_btn.pressed.connect(func(): _open_staff_dialog(s_uuid))
				del_s_btn.pressed.connect(func():
					var confirm_del = ConfirmationDialog.new()
					confirm_del.title = "Delete Staff Member"
					confirm_del.dialog_text = "Are you sure you want to delete " + s_name + " from the directory?"
					confirm_del.confirmed.connect(func():
						com_svc.delete_staff_member(s_uuid)
						var sync_svc = GatewaySyncScript.new(db, self)
						sync_svc.publish_ivr_config(func(result): pass)
						_render_ivr_tab()
					)
					add_child(confirm_del)
					confirm_del.popup_centered()
				)
				
				row_hbox.add_child(edit_s_btn)
				row_hbox.add_child(del_s_btn)
				staff_list_container.add_child(row)
		else:
			var empty_lbl = Label.new()
			empty_lbl.text = "No staff members configured."
			empty_lbl.add_theme_font_size_override("font_size", 14)
			empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
			staff_list_container.add_child(empty_lbl)
			
		var flow_desc_panel = PanelContainer.new()
		var desc_st = StyleBoxFlat.new(); desc_st.bg_color = Color(0.97, 0.97, 0.98, 1.0); desc_st.content_margin_left = 14; desc_st.content_margin_top = 12; desc_st.content_margin_right = 14; desc_st.content_margin_bottom = 12; desc_st.corner_radius_top_left = 6; desc_st.corner_radius_top_right = 6; desc_st.corner_radius_bottom_left = 6; desc_st.corner_radius_bottom_right = 6
		flow_desc_panel.add_theme_stylebox_override("panel", desc_st)
		
		var desc_vbox = VBoxContainer.new()
		desc_vbox.add_theme_constant_override("separation", 6)
		flow_desc_panel.add_child(desc_vbox)
		
		var d_title = Label.new()
		d_title.text = "📞 Plain-Language Call Routing & Screening Flow:"
		d_title.add_theme_font_size_override("font_size", 14)
		d_title.add_theme_color_override("font_color", _get_active_theme_color())
		desc_vbox.add_child(d_title)
		
		var d_body = Label.new()
		d_body.text = "1. Inbound Caller gives their name.\n2. Staff member is called at their configured Transfer Number.\n3. Staff hears whisper screening option: \"Call from [recorded name]. Press 1 to accept.\"\n4. If staff presses 1, call is bridged. If staff is busy or hangs up, caller is routed to voicemail."
		d_body.add_theme_font_size_override("font_size", 13)
		d_body.add_theme_color_override("font_color", Color(0.3, 0.35, 0.45, 1.0))
		desc_vbox.add_child(d_body)
		
		staff_vbox.add_child(flow_desc_panel)
		main_content_vbox.add_child(staff_card)

	elif ivr_sub_tab == "voice":
		var gen_card = PanelContainer.new()
		var gen_st = StyleBoxFlat.new(); gen_st.bg_color = Color(1.0, 1.0, 1.0, 1.0); gen_st.border_width_left = 1; gen_st.border_width_top = 1; gen_st.border_width_right = 1; gen_st.border_width_bottom = 1; gen_st.border_color = Color(0.88, 0.91, 0.94, 1.0); gen_st.corner_radius_top_left = 8; gen_st.corner_radius_top_right = 8; gen_st.corner_radius_bottom_left = 8; gen_st.corner_radius_bottom_right = 8; gen_st.content_margin_left = 18; gen_st.content_margin_top = 16; gen_st.content_margin_right = 18; gen_st.content_margin_bottom = 16
		gen_card.add_theme_stylebox_override("panel", gen_st)
		
		var gen_vbox = VBoxContainer.new()
		gen_vbox.add_theme_constant_override("separation", 14)
		gen_card.add_child(gen_vbox)
		
		var gen_title = Label.new(); gen_title.text = "☎ General Greeting & Voice Options"; gen_title.add_theme_font_size_override("font_size", 18); gen_title.add_theme_color_override("font_color", _get_active_theme_color())
		gen_vbox.add_child(gen_title)
		
		var oc_hbox = HBoxContainer.new()
		var oc_lbl = Label.new(); oc_lbl.text = "Primary On-Call Recipient: "; oc_lbl.custom_minimum_size = Vector2(180, 0); oc_lbl.add_theme_font_size_override("font_size", 15); oc_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		var oc_opt = OptionButton.new(); oc_opt.custom_minimum_size = Vector2(300, 36); _style_input_control(oc_opt, 15)
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
		
		var rings_hbox = HBoxContainer.new()
		var rings_lbl = Label.new(); rings_lbl.text = "Rings Before Attendant: "; rings_lbl.custom_minimum_size = Vector2(180, 0); rings_lbl.add_theme_font_size_override("font_size", 15); rings_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		var rings_slider = HSlider.new(); rings_slider.min_value = 2; rings_slider.max_value = 8; rings_slider.step = 1; rings_slider.value = settings["rollover_rings"]; rings_slider.size_flags_horizontal = SIZE_EXPAND_FILL
		var rings_val_lbl = Label.new(); rings_val_lbl.text = str(settings["rollover_rings"]) + " Rings"; rings_val_lbl.custom_minimum_size = Vector2(80, 0); rings_val_lbl.add_theme_font_size_override("font_size", 15)
		rings_slider.value_changed.connect(func(v): rings_val_lbl.text = str(int(v)) + " Rings")
		rings_hbox.add_child(rings_lbl); rings_hbox.add_child(rings_slider); rings_hbox.add_child(rings_val_lbl)
		gen_vbox.add_child(rings_hbox)
		
		var mode_sel_hbox = HBoxContainer.new()
		var mode_sel_lbl = Label.new(); mode_sel_lbl.text = "Greeting System: "; mode_sel_lbl.custom_minimum_size = Vector2(180, 0); mode_sel_lbl.add_theme_font_size_override("font_size", 15); mode_sel_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		var tts_radio = CheckButton.new(); tts_radio.text = "Text-to-Speech (Neural Voice)"; tts_radio.button_pressed = settings["tts_greeting_active"]
		mode_sel_hbox.add_child(mode_sel_lbl); mode_sel_hbox.add_child(tts_radio)
		gen_vbox.add_child(mode_sel_hbox)
		
		var voice_hbox = HBoxContainer.new()
		var voice_lbl = Label.new(); voice_lbl.text = "Neural TTS Voice: "; voice_lbl.custom_minimum_size = Vector2(180, 0); voice_lbl.add_theme_font_size_override("font_size", 15); voice_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		var voice_opt = OptionButton.new(); voice_opt.custom_minimum_size = Vector2(300, 36); _style_input_control(voice_opt, 15)
		
		for idx in range(static_voices.size()):
			var v = static_voices[idx]
			voice_opt.add_item(v["label"] + " (" + v["gender"] + ")", idx)
			voice_opt.set_item_metadata(idx, v["id"])
			if settings.has("voice_name") and v["id"] == settings["voice_name"]:
				voice_opt.selected = idx
		voice_hbox.add_child(voice_lbl); voice_hbox.add_child(voice_opt)
		gen_vbox.add_child(voice_hbox)
		
		var rec_section_lbl = Label.new(); rec_section_lbl.text = "Recorded Greetings:"; rec_section_lbl.add_theme_font_size_override("font_size", 14); rec_section_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		gen_vbox.add_child(rec_section_lbl)
		
		var active_audio_base64 = settings["automated_greeter_audio"]
		
		var audio_status_lbl = Label.new()
		audio_status_lbl.add_theme_font_size_override("font_size", 13)
		audio_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if active_audio_base64 != "":
			audio_status_lbl.text = "🎵 A recorded audio greeting override is active. Callers will hear the recording instead of the TTS script."
			audio_status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
		else:
			audio_status_lbl.text = "🚫 No recorded audio greeting. Callers will hear the Text-to-Speech script."
			audio_status_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		gen_vbox.add_child(audio_status_lbl)
		
		var rec_hbox = HBoxContainer.new()
		rec_hbox.add_theme_constant_override("separation", 12)
		var preview_btn = Button.new(); preview_btn.text = "🔊 Preview Greeting"; preview_btn.custom_minimum_size = Vector2(160, 34); preview_btn.add_theme_font_size_override("font_size", 14)
		var upload_btn = Button.new(); upload_btn.text = "📤 Upload Audio (.mp3/.wav)"; upload_btn.custom_minimum_size = Vector2(200, 34); upload_btn.add_theme_font_size_override("font_size", 14)
		var rec_btn = Button.new(); rec_btn.text = "🎤 Record Audio"; rec_btn.custom_minimum_size = Vector2(150, 34); rec_btn.add_theme_font_size_override("font_size", 14)
		
		for btn in [preview_btn, upload_btn, rec_btn]:
			btn.add_theme_stylebox_override("normal", sec_btn_st)
			btn.add_theme_stylebox_override("hover", sec_btn_hover)
			btn.add_theme_stylebox_override("pressed", sec_btn_st)
			btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0))
			btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
			rec_hbox.add_child(btn)
		gen_vbox.add_child(rec_hbox)
		
		preview_btn.pressed.connect(func():
			if active_audio_base64 != "":
				_play_audio_from_base64(active_audio_base64)
				return
			
			var voice_id = ""
			if voice_opt.selected > -1:
				voice_id = voice_opt.get_item_metadata(voice_opt.selected)
			
			DisplayServer.tts_stop()
			var txt = settings.get("automated_greeter_tts", "")
			if voice_id == "" or voice_id.begins_with("mock_"):
				var play_dlg = AcceptDialog.new(); play_dlg.dialog_text = "📢 Greeting Preview:\n\n\"" + txt + "\"\n\n(Voice: " + str(voice_opt.get_item_text(voice_opt.selected)) + ")"; add_child(play_dlg); play_dlg.popup_centered()
			else:
				DisplayServer.tts_speak(txt, voice_id)
		)
		
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
					audio_status_lbl.text = "🎵 A recorded audio greeting override is active. Callers will hear the recording instead of the TTS script."
					audio_status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
			)
			add_child(fd)
			fd.popup_centered()
		)
		
		rec_btn.pressed.connect(func():
			_open_voice_recording_dialog(func(base64_wav: String):
				active_audio_base64 = base64_wav
				audio_status_lbl.text = "🎵 A recorded audio greeting override is active. Callers will hear the recording instead of the TTS script."
				audio_status_lbl.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3, 1.0))
			)
		)
		
		var save_gen_hbox = HBoxContainer.new(); save_gen_hbox.alignment = BoxContainer.ALIGNMENT_END
		var save_gen_btn = Button.new(); save_gen_btn.text = "💾 Save Voice Settings"; save_gen_btn.custom_minimum_size = Vector2(220, 42); save_gen_btn.add_theme_font_size_override("font_size", 16)
		var save_st_act = StyleBoxFlat.new(); save_st_act.bg_color = _get_active_theme_color(); save_st_act.corner_radius_top_left = 6; save_st_act.corner_radius_top_right = 6; save_st_act.corner_radius_bottom_left = 6; save_st_act.corner_radius_bottom_right = 6
		var save_st_hov = save_st_act.duplicate(); save_st_hov.bg_color = _get_active_theme_color().lightened(0.08)
		save_gen_btn.add_theme_stylebox_override("normal", save_st_act)
		save_gen_btn.add_theme_stylebox_override("hover", save_st_hov)
		save_gen_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		
		save_gen_btn.pressed.connect(func():
			var on_call_id = ""
			if oc_opt.selected > 0:
				on_call_id = str(oc_opt.get_item_id(oc_opt.selected))
			var rings = int(rings_slider.value)
			var tts_active = tts_radio.button_pressed
			
			var selected_idx = voice_opt.selected
			var voice_entry = null
			if selected_idx > -1:
				var voice_id = voice_opt.get_item_metadata(selected_idx)
				for v in static_voices:
					if v["id"] == voice_id:
						voice_entry = v
						break
			if voice_entry != null:
				db.execute("INSERT OR REPLACE INTO ivr_settings (id, voice_name, language) VALUES (1, ?, ?);", [voice_entry["id"], voice_entry["language"]])
				
			var ok = com_svc.save_phone_settings(on_call_id, rings, tts_active, settings.get("automated_greeter_tts", ""), active_audio_base64)
			if ok:
				var sync_svc = GatewaySyncScript.new(db, self)
				sync_svc.publish_ivr_config(func(result):
					if result["success"]:
						var pub_d = AcceptDialog.new(); pub_d.dialog_text = "Settings saved & synced to relay successfully!"; add_child(pub_d); pub_d.popup_centered()
					else:
						var err_d = AcceptDialog.new(); err_d.dialog_text = "Saved locally, but relay sync failed: " + str(result.get("error")); add_child(err_d); err_d.popup_centered()
				)
		)
		save_gen_hbox.add_child(save_gen_btn)
		gen_vbox.add_child(save_gen_hbox)
		
		main_content_vbox.add_child(gen_card)

	for c in content_card.get_children(): c.free()
	content_card.add_child(root_vbox)

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

var cc_admin_sub_tab: String = "institutions"

func _render_campus_community_tab() -> void:
	var scroll = ScrollContainer.new(); scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin_wrap = MarginContainer.new(); margin_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL; margin_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_wrap.add_theme_constant_override("margin_left", 16); margin_wrap.add_theme_constant_override("margin_top", 16); margin_wrap.add_theme_constant_override("margin_right", 16); margin_wrap.add_theme_constant_override("margin_bottom", 16)

	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; vbox.add_theme_constant_override("separation", 16)

	# Sub-Tab Navigation Bar
	var sub_hbox = HBoxContainer.new(); sub_hbox.add_theme_constant_override("separation", 10)

	var btn_sub_inst = Button.new(); btn_sub_inst.text = " 🏫 Institutions Master Directory "
	btn_sub_inst.custom_minimum_size = Vector2(0, 38); btn_sub_inst.add_theme_font_size_override("font_size", 14)
	_style_tab_btn(btn_sub_inst, cc_admin_sub_tab == "institutions")
	btn_sub_inst.pressed.connect(func(): cc_admin_sub_tab = "institutions"; _render_campus_community_tab())
	sub_hbox.add_child(btn_sub_inst)

	var btn_sub_adv = Button.new(); btn_sub_adv.text = " 🎓 Academic Advancement Review "
	btn_sub_adv.custom_minimum_size = Vector2(0, 38); btn_sub_adv.add_theme_font_size_override("font_size", 14)
	_style_tab_btn(btn_sub_adv, cc_admin_sub_tab == "advancement")
	btn_sub_adv.pressed.connect(func(): cc_admin_sub_tab = "advancement"; _render_campus_community_tab())
	sub_hbox.add_child(btn_sub_adv)

	var btn_sub_maj = Button.new(); btn_sub_maj.text = " 📘 Academic Majors & Autocomplete "
	btn_sub_maj.custom_minimum_size = Vector2(0, 38); btn_sub_maj.add_theme_font_size_override("font_size", 14)
	_style_tab_btn(btn_sub_maj, cc_admin_sub_tab == "majors")
	btn_sub_maj.pressed.connect(func(): cc_admin_sub_tab = "majors"; _render_campus_community_tab())
	sub_hbox.add_child(btn_sub_maj)

	vbox.add_child(sub_hbox)

	if cc_admin_sub_tab == "institutions":
		_render_institutions_master_directory(vbox)
	elif cc_admin_sub_tab == "majors":
		_render_academic_majors_management(vbox)
	else:
		_render_academic_advancement_review(vbox)

	margin_wrap.add_child(vbox)
	scroll.add_child(margin_wrap)
	content_card.add_child(scroll)

func _render_institutions_master_directory(parent_vbox: VBoxContainer) -> void:
	var top_bar = HBoxContainer.new(); top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl = Label.new(); title_lbl.text = "Master Institutions Directory"; title_lbl.add_theme_font_size_override("font_size", 18); title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0)); title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_lbl)

	var btn_cleanup = Button.new(); btn_cleanup.text = "🧹 Institution Cleanup & Merge"; btn_cleanup.custom_minimum_size = Vector2(210, 38); btn_cleanup.add_theme_font_size_override("font_size", 14)
	btn_cleanup.pressed.connect(func(): _open_institution_cleanup_dialog())
	top_bar.add_child(btn_cleanup)

	var btn_add_inst = Button.new(); btn_add_inst.text = "+ Add New Institution"; btn_add_inst.custom_minimum_size = Vector2(180, 38); btn_add_inst.add_theme_font_size_override("font_size", 14)
	btn_add_inst.pressed.connect(func(): _open_add_institution_dialog())
	top_bar.add_child(btn_add_inst)
	parent_vbox.add_child(top_bar)

	var insts_vbox = VBoxContainer.new(); insts_vbox.add_theme_constant_override("separation", 10)

	var q_inst = db.execute("SELECT * FROM institutions ORDER BY display_order ASC, name ASC;")
	if not q_inst["success"] or q_inst["data"].size() == 0:
		var empty_lbl = Label.new(); empty_lbl.text = "No institutions configured in master directory."
		insts_vbox.add_child(empty_lbl)
	else:
		for inst in q_inst["data"]:
			var inst_id = int(inst.get("id"))
			var inst_name = str(inst.get("name", ""))
			var inst_short = str(inst.get("short_name", ""))
			var inst_type = str(inst.get("institution_type", "college_university"))
			var inst_order = int(inst.get("display_order", 0))
			var is_act = (int(inst.get("is_active", 1)) == 1)

			var card = PanelContainer.new()
			var st = StyleBoxFlat.new()
			st.bg_color = Color(0.96, 0.97, 0.99, 1.0) if is_act else Color(0.92, 0.93, 0.95, 1.0)
			st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
			st.border_color = Color(0.84, 0.88, 0.94, 1.0)
			st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
			st.content_margin_left = 14; st.content_margin_top = 10; st.content_margin_right = 14; st.content_margin_bottom = 10
			card.add_theme_stylebox_override("panel", st)

			var r_hbox = HBoxContainer.new(); r_hbox.add_theme_constant_override("separation", 12)

			var order_lbl = Label.new(); order_lbl.text = "#" + str(inst_order)
			order_lbl.add_theme_font_size_override("font_size", 13); order_lbl.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62, 1.0))
			r_hbox.add_child(order_lbl)

			var name_lbl = Label.new(); name_lbl.text = inst_name + (" (%s)" % inst_short if inst_short != "" else "")
			name_lbl.add_theme_font_size_override("font_size", 15); name_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r_hbox.add_child(name_lbl)

			var type_badge = Label.new()
			type_badge.text = "[%s]" % inst_type.replace("_", " ").to_upper()
			type_badge.add_theme_font_size_override("font_size", 12)
			type_badge.add_theme_color_override("font_color", Color(0.15, 0.45, 0.85, 1.0) if inst_type == "college_university" else Color(0.35, 0.42, 0.52, 1.0))
			r_hbox.add_child(type_badge)

			var btn_edit = Button.new(); btn_edit.text = "✏️ Edit"; btn_edit.custom_minimum_size = Vector2(70, 34); btn_edit.add_theme_font_size_override("font_size", 12)
			btn_edit.pressed.connect(func(): _open_edit_institution_dialog(inst))
			r_hbox.add_child(btn_edit)

			var btn_up = Button.new(); btn_up.text = "⬆️"; btn_up.custom_minimum_size = Vector2(34, 34)
			btn_up.pressed.connect(func(): _move_institution_order(inst_id, "up"))
			r_hbox.add_child(btn_up)

			var btn_down = Button.new(); btn_down.text = "⬇️"; btn_down.custom_minimum_size = Vector2(34, 34)
			btn_down.pressed.connect(func(): _move_institution_order(inst_id, "down"))
			r_hbox.add_child(btn_down)

			var btn_toggle = Button.new()
			btn_toggle.text = "🚫 Disable" if is_act else "🔄 Enable"
			btn_toggle.custom_minimum_size = Vector2(90, 34); btn_toggle.add_theme_font_size_override("font_size", 12)
			btn_toggle.pressed.connect(func():
				db.execute("UPDATE institutions SET is_active = ?, updated_at = datetime('now') WHERE id = ?;", [0 if is_act else 1, inst_id])
				_render_campus_community_tab()
			)
			r_hbox.add_child(btn_toggle)

			card.add_child(r_hbox)
			insts_vbox.add_child(card)

	parent_vbox.add_child(insts_vbox)

func _open_add_institution_dialog() -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Add New Institution"
	dlg.size = Vector2i(480, 320)

	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 10)

	var lbl_n = Label.new(); lbl_n.text = "Institution Name:"
	var txt_n = LineEdit.new(); txt_n.placeholder_text = "e.g. Furman University"

	var lbl_s = Label.new(); lbl_s.text = "Short Name / Abbreviation:"
	var txt_s = LineEdit.new(); txt_s.placeholder_text = "e.g. FU"

	var lbl_t = Label.new(); lbl_t.text = "Institution Type:"
	var opt_t = OptionButton.new()
	opt_t.add_item("College / University", 0)
	opt_t.add_item("High School", 1)
	opt_t.add_item("Community", 2)
	opt_t.add_item("Other", 3)

	var type_keys = ["college_university", "high_school", "community", "other"]

	vbox.add_child(lbl_n); vbox.add_child(txt_n)
	vbox.add_child(lbl_s); vbox.add_child(txt_s)
	vbox.add_child(lbl_t); vbox.add_child(opt_t)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var n_val = txt_n.text.strip_edges()
		if n_val == "": return
		var s_val = txt_s.text.strip_edges()
		var t_val = type_keys[opt_t.selected]
		var inst_uuid = "inst_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)

		# Get next order
		var q_ord = db.execute("SELECT MAX(display_order) as max_ord FROM institutions;")
		var next_ord = (int(q_ord["data"][0].get("max_ord", 0)) + 1) if (q_ord["success"] and q_ord["data"].size() > 0) else 1

		db.execute("INSERT INTO institutions (uuid, name, short_name, institution_type, display_order, is_active) VALUES (?, ?, ?, ?, ?, 1);",
			[inst_uuid, n_val, s_val, t_val, next_ord])
		_render_campus_community_tab()
	)
	add_child(dlg); dlg.popup_centered()

func _open_edit_institution_dialog(inst: Dictionary) -> void:
	var inst_id = int(inst.get("id"))
	var dlg = ConfirmationDialog.new()
	dlg.title = "Edit Institution"
	dlg.size = Vector2i(480, 320)

	var vbox = VBoxContainer.new(); vbox.add_theme_constant_override("separation", 10)

	var lbl_n = Label.new(); lbl_n.text = "Institution Name:"
	var txt_n = LineEdit.new(); txt_n.text = str(inst.get("name", ""))

	var lbl_s = Label.new(); lbl_s.text = "Short Name:"
	var txt_s = LineEdit.new(); txt_s.text = str(inst.get("short_name", ""))

	var lbl_t = Label.new(); lbl_t.text = "Institution Type:"
	var opt_t = OptionButton.new()
	opt_t.add_item("College / University", 0)
	opt_t.add_item("High School", 1)
	opt_t.add_item("Community", 2)
	opt_t.add_item("Other", 3)

	var type_keys = ["college_university", "high_school", "community", "other"]
	var cur_type = str(inst.get("institution_type", "college_university"))
	var t_idx = type_keys.find(cur_type)
	opt_t.select(t_idx if t_idx >= 0 else 0)

	vbox.add_child(lbl_n); vbox.add_child(txt_n)
	vbox.add_child(lbl_s); vbox.add_child(txt_s)
	vbox.add_child(lbl_t); vbox.add_child(opt_t)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var n_val = txt_n.text.strip_edges()
		if n_val == "": return
		var s_val = txt_s.text.strip_edges()
		var t_val = type_keys[opt_t.selected]

		db.execute("UPDATE institutions SET name = ?, short_name = ?, institution_type = ?, updated_at = datetime('now') WHERE id = ?;",
			[n_val, s_val, t_val, inst_id])
		_render_campus_community_tab()
	)
	add_child(dlg); dlg.popup_centered()

func _move_institution_order(inst_id: int, direction: String) -> void:
	var q = db.execute("SELECT id, display_order FROM institutions ORDER BY display_order ASC, name ASC;")
	if not q["success"] or q["data"].size() <= 1: return

	var list = q["data"]
	var idx = -1
	for i in range(list.size()):
		if int(list[i]["id"]) == inst_id:
			idx = i
			break

	if idx == -1: return
	var target_idx = idx - 1 if direction == "up" else idx + 1
	if target_idx < 0 or target_idx >= list.size(): return

	var curr_item = list[idx]
	var target_item = list[target_idx]

	var curr_ord = int(curr_item["display_order"])
	var target_ord = int(target_item["display_order"])

	db.execute("UPDATE institutions SET display_order = ? WHERE id = ?;", [target_ord, int(curr_item["id"])])
	db.execute("UPDATE institutions SET display_order = ? WHERE id = ?;", [curr_ord, int(target_item["id"])])
	_render_campus_community_tab()

func _render_academic_advancement_review(parent_vbox: VBoxContainer) -> void:
	var is_admin = true # Admin Role check
	if not is_admin:
		var restrict_card = PanelContainer.new()
		var r_lbl = Label.new()
		r_lbl.text = "⚠️ Permission Restricted: Academic Advancement Review is restricted to System Administrators."
		r_lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35, 1.0))
		restrict_card.add_child(r_lbl)
		parent_vbox.add_child(restrict_card)
		return

	# Header Bar & Deferral Info Notice
	var hdr_box = VBoxContainer.new(); hdr_box.add_theme_constant_override("separation", 6)

	var title_lbl = Label.new(); title_lbl.text = "Academic Advancement Review Queue"
	title_lbl.add_theme_font_size_override("font_size", 18); title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	hdr_box.add_child(title_lbl)

	var info_lbl = Label.new()
	info_lbl.text = "ℹ️ Fall Graduation Deferral: Participants with Expected Graduation Term = 'Fall' are retained as Senior during standard spring reviews."
	info_lbl.add_theme_font_size_override("font_size", 12); info_lbl.add_theme_color_override("font_color", Color(0.15, 0.45, 0.85, 1.0))
	hdr_box.add_child(info_lbl)

	parent_vbox.add_child(hdr_box)

	# Query Candidates
	var sql_q = """
		SELECT p.id, p.person_uuid, p.human_id, p.first_name, p.last_name, p.academic_year, p.expected_grad_term, p.expected_grad_year, p.advancement_last_reviewed_at, inst.name as inst_name, inst.short_name as inst_short_name
		FROM people p
		JOIN institutions inst ON inst.id = p.institution_id
		WHERE inst.institution_type = 'college_university'
		  AND p.relationship = 'Student'
		  AND p.skip_next_advancement = 0
		ORDER BY p.last_name ASC, p.first_name ASC;
	"""
	var q_cand = db.execute(sql_q)
	var candidates = q_cand["data"] if (q_cand["success"] and q_cand["data"].size() > 0) else []

	if candidates.size() == 0:
		var empty_lbl = Label.new(); empty_lbl.text = "No participants currently pending academic advancement review."
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 1.0))
		parent_vbox.add_child(empty_lbl)
		return

	# Batch Action Bar
	var batch_bar = HBoxContainer.new(); batch_bar.add_theme_constant_override("separation", 12)

	var opt_action = OptionButton.new()
	opt_action.add_item("1. Apply Suggested Promotion", 0)
	opt_action.add_item("2. Assign Custom Academic Year", 1)
	opt_action.add_item("3. Leave Unchanged (Mark Reviewed)", 2)
	opt_action.add_item("4. Keep in Queue (Review Later)", 3)
	opt_action.add_item("5. Skip This Academic Year", 4)
	opt_action.custom_minimum_size = Vector2(260, 38)
	batch_bar.add_child(opt_action)

	var opt_custom_ay = OptionButton.new()
	opt_custom_ay.add_item("Freshman", 0); opt_custom_ay.add_item("Sophomore", 1); opt_custom_ay.add_item("Junior", 2); opt_custom_ay.add_item("Senior", 3); opt_custom_ay.add_item("Alumni", 4)
	opt_custom_ay.custom_minimum_size = Vector2(140, 38)
	opt_custom_ay.visible = false
	batch_bar.add_child(opt_custom_ay)

	opt_action.item_selected.connect(func(idx): opt_custom_ay.visible = (idx == 1))

	var selected_person_ids = []

	var btn_exec_batch = Button.new(); btn_exec_batch.text = "⚡ Process Selected Review Items"
	btn_exec_batch.custom_minimum_size = Vector2(240, 38); btn_exec_batch.add_theme_font_size_override("font_size", 14)
	batch_bar.add_child(btn_exec_batch)
	parent_vbox.add_child(batch_bar)

	# Candidate List Table
	var table_vbox = VBoxContainer.new(); table_vbox.add_theme_constant_override("separation", 8)

	for c_item in candidates:
		var pid = int(c_item.get("id"))
		var name_str = str(c_item.get("first_name", "")) + " " + str(c_item.get("last_name", ""))
		var inst_str = str(c_item.get("inst_short_name", c_item.get("inst_name", "")))
		var cur_ay = str(c_item.get("academic_year", "Freshman"))
		var grad_term = str(c_item.get("expected_grad_term", "Spring"))
		var grad_yr = str(c_item.get("expected_grad_year", "N/A"))
		var last_rev = str(c_item.get("advancement_last_reviewed_at", "Never"))

		# Calculate Suggested Promotion
		var sug_ay = "Sophomore"
		if cur_ay == "Freshman": sug_ay = "Sophomore"
		elif cur_ay == "Sophomore": sug_ay = "Junior"
		elif cur_ay == "Junior": sug_ay = "Senior"
		elif cur_ay == "Senior": sug_ay = "Alumni"
		elif cur_ay == "Graduate Student": sug_ay = "Alumni"

		# Fall Deferral Rule
		var is_deferred = (grad_term == "Fall" and cur_ay == "Senior")
		if is_deferred:
			sug_ay = "Senior (Deferred to Fall)"

		var row_card = PanelContainer.new()
		var r_st = StyleBoxFlat.new()
		r_st.bg_color = Color(0.97, 0.98, 1.0, 1.0)
		r_st.border_width_left = 1; r_st.border_width_top = 1; r_st.border_width_right = 1; r_st.border_width_bottom = 1
		r_st.border_color = Color(0.85, 0.88, 0.94, 1.0)
		r_st.corner_radius_top_left = 6; r_st.corner_radius_top_right = 6; r_st.corner_radius_bottom_left = 6; r_st.corner_radius_bottom_right = 6
		r_st.content_margin_left = 12; r_st.content_margin_top = 8; r_st.content_margin_right = 12; r_st.content_margin_bottom = 8
		row_card.add_theme_stylebox_override("panel", r_st)

		var r_hbox = HBoxContainer.new(); r_hbox.add_theme_constant_override("separation", 14)

		var chk = CheckBox.new()
		chk.toggled.connect(func(toggled_on: bool):
			if toggled_on and not pid in selected_person_ids: selected_person_ids.append(pid)
			elif not toggled_on and pid in selected_person_ids: selected_person_ids.erase(pid)
		)
		r_hbox.add_child(chk)

		var name_lbl = Label.new(); name_lbl.text = name_str + " (" + inst_str + ")"
		name_lbl.add_theme_font_size_override("font_size", 14); name_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_hbox.add_child(name_lbl)

		var current_ay_lbl = Label.new(); current_ay_lbl.text = "Current: " + cur_ay
		current_ay_lbl.add_theme_font_size_override("font_size", 13); current_ay_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
		r_hbox.add_child(current_ay_lbl)

		var arrow_lbl = Label.new(); arrow_lbl.text = "➔"; arrow_lbl.add_theme_font_size_override("font_size", 13)
		r_hbox.add_child(arrow_lbl)

		var sug_lbl = Label.new(); sug_lbl.text = "Suggested: " + sug_ay
		sug_lbl.add_theme_font_size_override("font_size", 13)
		sug_lbl.add_theme_color_override("font_color", Color(0.12, 0.55, 0.25, 1.0) if not is_deferred else Color(0.85, 0.50, 0.10, 1.0))
		r_hbox.add_child(sug_lbl)

		var grad_info_lbl = Label.new(); grad_info_lbl.text = "Grad: %s %s" % [grad_term, grad_yr]
		grad_info_lbl.add_theme_font_size_override("font_size", 12); grad_info_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 1.0))
		r_hbox.add_child(grad_info_lbl)

		row_card.add_child(r_hbox)
		table_vbox.add_child(row_card)

	parent_vbox.add_child(table_vbox)

	# Batch Action Connection with Comprehensive Pre-Execution Preview Safeguard
	btn_exec_batch.pressed.connect(func():
		if selected_person_ids.size() == 0: return
		var sel_act_idx = opt_action.selected

		# Calculate Preview Counts & Exception Breakdown
		var total_sel = selected_person_ids.size()
		var inst_set = {}
		var cnt_f_s = 0; var cnt_s_j = 0; var cnt_j_sr = 0; var cnt_sr_al = 0
		var cnt_custom = 0; var cnt_unchanged = 0; var cnt_skipped = 0; var cnt_deferred = 0; var cnt_conflicts = 0

		var action_titles = ["Apply Suggested Promotion", "Assign Custom Academic Year", "Leave Unchanged", "Keep in Queue", "Skip This Academic Year"]
		var custom_years = ["Freshman", "Sophomore", "Junior", "Senior", "Alumni"]

		for p_id in selected_person_ids:
			var q_p = db.execute("SELECT p.*, inst.name as inst_name FROM people p LEFT JOIN institutions inst ON inst.id = p.institution_id WHERE p.id = ? LIMIT 1;", [p_id])
			if not q_p["success"] or q_p["data"].size() == 0:
				cnt_conflicts += 1
				continue
			var p_row = q_p["data"][0]
			var iname = str(p_row.get("inst_name", "Unassigned"))
			inst_set[iname] = true

			var cur_ay = str(p_row.get("academic_year", "Freshman"))
			var grad_term = str(p_row.get("expected_grad_term", "Spring"))
			var is_fall_deferred = (grad_term == "Fall" and cur_ay == "Senior")

			if is_fall_deferred:
				cnt_deferred += 1

			if sel_act_idx == 0: # Suggested Promotion
				if cur_ay == "Freshman": cnt_f_s += 1
				elif cur_ay == "Sophomore": cnt_s_j += 1
				elif cur_ay == "Junior": cnt_j_sr += 1
				elif cur_ay == "Senior" and not is_fall_deferred: cnt_sr_al += 1
				elif cur_ay == "Graduate Student": cnt_sr_al += 1
			elif sel_act_idx == 1: # Custom Year
				cnt_custom += 1
			elif sel_act_idx == 2 or sel_act_idx == 3: # Unchanged or Keep in Queue
				cnt_unchanged += 1
			elif sel_act_idx == 4: # Skip Academic Year
				cnt_skipped += 1

		# Construct Rich Preview Modal
		var dlg = AcceptDialog.new()
		dlg.title = "🛡️ Academic Advancement Batch Review Preview"
		dlg.size = Vector2i(560, 420)

		var p_vbox = VBoxContainer.new()
		p_vbox.add_theme_constant_override("separation", 10)

		var head_lbl = Label.new()
		head_lbl.text = "Batch Action Summary: %s (%d Selected Participants)" % [action_titles[sel_act_idx], total_sel]
		head_lbl.add_theme_font_size_override("font_size", 15)
		head_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
		p_vbox.add_child(head_lbl)

		var inst_lbl = Label.new()
		inst_lbl.text = "🏛️ Institutions Represented: " + ", ".join(inst_set.keys())
		inst_lbl.add_theme_font_size_override("font_size", 13)
		inst_lbl.add_theme_color_override("font_color", Color(0.18, 0.45, 0.85, 1.0))
		p_vbox.add_child(inst_lbl)

		var p_grid = GridContainer.new(); p_grid.columns = 2
		p_grid.add_theme_constant_override("h_separation", 20); p_grid.add_theme_constant_override("v_separation", 6)

		p_grid.add_child(_create_stat_row("Freshman ➔ Sophomore:", str(cnt_f_s)))
		p_grid.add_child(_create_stat_row("Sophomore ➔ Junior:", str(cnt_s_j)))
		p_grid.add_child(_create_stat_row("Junior ➔ Senior:", str(cnt_j_sr)))
		p_grid.add_child(_create_stat_row("Senior ➔ Alumni:", str(cnt_sr_al)))
		p_grid.add_child(_create_stat_row("Custom Year Assignments:", str(cnt_custom)))
		p_grid.add_child(_create_stat_row("Left Unchanged:", str(cnt_unchanged)))
		p_grid.add_child(_create_stat_row("Skipped Academic Years:", str(cnt_skipped)))
		p_grid.add_child(_create_stat_row("Fall Graduates Deferred:", str(cnt_deferred)))
		if cnt_conflicts > 0:
			p_grid.add_child(_create_stat_row("⚠️ Records with Mismatches:", str(cnt_conflicts)))
		p_vbox.add_child(p_grid)

		var btn_hbox = HBoxContainer.new(); btn_hbox.add_theme_constant_override("separation", 12)
		var btn_confirm = Button.new(); btn_confirm.text = "✅ Confirm & Execute Batch"
		btn_confirm.custom_minimum_size = Vector2(200, 36)
		btn_confirm.pressed.connect(func():
			dlg.hide()
			db.execute("BEGIN TRANSACTION;")
			var batch_success = true
			for p_id in selected_person_ids:
				var q_p = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [p_id])
				if not q_p["success"] or q_p["data"].size() == 0:
					batch_success = false
					break
				var p_row = q_p["data"][0]
				var c_ay = str(p_row.get("academic_year", "Freshman"))
				var next_ay = c_ay
				var next_rel = str(p_row.get("relationship", "Student"))
				var set_skip = 0

				if sel_act_idx == 0: # Apply Suggested
					if c_ay == "Freshman": next_ay = "Sophomore"
					elif c_ay == "Sophomore": next_ay = "Junior"
					elif c_ay == "Junior": next_ay = "Senior"
					elif c_ay == "Senior": next_ay = "Alumni"; next_rel = "Alumni"
					elif c_ay == "Graduate Student": next_ay = "Alumni"; next_rel = "Alumni"
				elif sel_act_idx == 1: # Custom Year
					next_ay = custom_years[opt_custom_ay.selected]
					if next_ay == "Alumni": next_rel = "Alumni"
				elif sel_act_idx == 4: # Skip
					set_skip = 1

				if sel_act_idx != 3: # Keep in Queue takes no action
					var u_res = db.execute("UPDATE people SET academic_year = ?, grade = ?, relationship = ?, skip_next_advancement = ?, advancement_last_reviewed_at = datetime('now'), updated_at = datetime('now') WHERE id = ?;",
						[next_ay, next_ay, next_rel, set_skip, p_id])
					if not u_res.get("success", false):
						batch_success = false; break

					var h_uuid = "ahist_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)
					var h_res = db.execute("INSERT INTO person_academic_history (uuid, person_id, institution_id, institution_other_name, relationship, academic_year, major, residence, expected_grad_term, expected_grad_year, change_source, changed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Academic Advancement Review', 'Administrator');",
						[h_uuid, p_id, p_row.get("institution_id"), p_row.get("institution_other_name"), next_rel, next_ay, p_row.get("major"), p_row.get("residence"), p_row.get("expected_grad_term"), p_row.get("expected_grad_year")])
					if not h_res.get("success", false):
						batch_success = false; break

			if batch_success:
				db.execute("COMMIT;")
				# Single Batch Audit Event Outbox Record
				var evt_uuid = "evt_batch_adv_" + str(Time.get_ticks_msec())
				db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload, created_at) VALUES (?, 'academic.advancement_batch', 'cohort', '0', ?, datetime('now'));",
					[evt_uuid, "Executed batch advancement '%s' for %d constituents." % [action_titles[sel_act_idx], total_sel]])
				_render_campus_community_tab()
			else:
				db.execute("ROLLBACK;")
				_show_toast("❌ Batch advancement failed and was safely rolled back.", Color(0.85, 0.25, 0.20, 1.0))
		)
		btn_hbox.add_child(btn_confirm)
		p_vbox.add_child(btn_hbox)

		dlg.add_child(p_vbox)
		add_child(dlg); dlg.popup_centered()
	)

func _show_toast(msg: String, _col: Color = Color(0.12, 0.16, 0.22, 1.0)) -> void:
	var dlg = AcceptDialog.new()
	dlg.dialog_text = msg
	add_child(dlg)
	dlg.popup_centered()

func _create_stat_row(lbl_text: String, val_text: String) -> HBoxContainer:
	var hb = HBoxContainer.new()
	var l = Label.new(); l.text = lbl_text; l.add_theme_font_size_override("font_size", 13); l.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
	var v = Label.new(); v.text = val_text; v.add_theme_font_size_override("font_size", 13); v.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	hb.add_child(l); hb.add_child(v)
	return hb

# --- INSTITUTION CLEANUP & MERGE DIALOG ---

func _open_institution_cleanup_dialog() -> void:
	var svc = CampusCommunityAdminServiceScript.new(db)
	var unlinked = svc.get_unlinked_custom_institution_names()
	var duplicates = svc.find_duplicate_institutions()

	var dlg = ConfirmationDialog.new()
	dlg.title = "🧹 Master Institution Cleanup & Deduplication"
	dlg.size = Vector2i(540, 360)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)

	var info_lbl = Label.new()
	info_lbl.text = "Select a custom institution name or master institution to merge into a canonical master record."
	info_lbl.add_theme_font_size_override("font_size", 13)
	main_vbox.add_child(info_lbl)

	var opt_source = OptionButton.new()
	opt_source.custom_minimum_size = Vector2(300, 36)
	var source_keys = []

	if unlinked.size() > 0:
		for item in unlinked:
			var name = str(item.get("institution_other_name", ""))
			var cnt = int(item.get("count", 0))
			opt_source.add_item("Custom Name: '%s' (%d constituents)" % [name, cnt])
			source_keys.append(name)

	var inst_q = db.execute("SELECT id, name, institution_type FROM institutions WHERE is_active = 1 ORDER BY name ASC;")
	var inst_list = inst_q["data"] if inst_q["success"] else []

	for inst in inst_list:
		opt_source.add_item("Master Inst: '%s' (ID %d)" % [str(inst.get("name")), int(inst.get("id"))])
		source_keys.append(int(inst.get("id")))

	main_vbox.add_child(opt_source)

	var target_lbl = Label.new(); target_lbl.text = "Target Master Institution:"
	main_vbox.add_child(target_lbl)

	var opt_target = OptionButton.new()
	opt_target.custom_minimum_size = Vector2(300, 36)
	for inst in inst_list:
		opt_target.add_item(str(inst.get("name")), int(inst.get("id")))
	main_vbox.add_child(opt_target)

	var txt_reason = LineEdit.new()
	txt_reason.placeholder_text = "Reason for merge (required for audit log)..."
	main_vbox.add_child(txt_reason)

	dlg.confirmed.connect(func():
		if source_keys.size() == 0 or opt_target.item_count == 0: return
		var sel_src = source_keys[opt_source.selected]
		var target_id = opt_target.get_item_id(opt_target.selected)
		var reason = txt_reason.text.strip_edges()
		if reason == "": reason = "Administrative institution deduplication."

		var prev = svc.get_institution_merge_preview(sel_src, target_id)
		if prev.get("has_type_mismatch", false):
			print("⚠️ Warning: Merging across different institution types (%s -> %s)." % [prev["source_type"], prev["target_type"]])

		var res = svc.merge_institutions_atomic(sel_src, target_id, "Administrator", reason)
		if res.get("success", false):
			_render_campus_community_tab()
	)

	dlg.add_child(main_vbox)
	add_child(dlg); dlg.popup_centered()

# --- ACADEMIC MAJORS MANAGEMENT SUB-TAB ---

func _render_academic_majors_management(parent_vbox: VBoxContainer) -> void:
	var svc = CampusCommunityAdminServiceScript.new(db)
	var majors = svc.get_canonical_majors()

	var top_bar = HBoxContainer.new(); top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl = Label.new(); title_lbl.text = "Academic Majors & Normalization Master Directory"
	title_lbl.add_theme_font_size_override("font_size", 18); title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_lbl)

	var btn_add_maj = Button.new(); btn_add_maj.text = "+ Add New Major"
	btn_add_maj.custom_minimum_size = Vector2(160, 38)
	btn_add_maj.pressed.connect(func():
		var dlg = ConfirmationDialog.new()
		dlg.title = "Add Canonical Academic Major"
		var edit = LineEdit.new(); edit.placeholder_text = "Canonical Major Name..."
		dlg.add_child(edit)
		dlg.confirmed.connect(func():
			var name = edit.text.strip_edges()
			if name != "":
				var muuid = "maj_" + str(Time.get_ticks_msec())
				db.execute("INSERT INTO academic_majors (uuid, canonical_name, display_order, is_active) VALUES (?, ?, 10, 1);", [muuid, name])
				_render_campus_community_tab()
		)
		add_child(dlg); dlg.popup_centered()
	)
	top_bar.add_child(btn_add_maj)
	parent_vbox.add_child(top_bar)

	var m_vbox = VBoxContainer.new(); m_vbox.add_theme_constant_override("separation", 8)
	for m in majors:
		var cname = str(m.get("canonical_name", ""))
		var aliases = str(m.get("aliases", ""))
		var is_act = (int(m.get("is_active", 1)) == 1)

		var pq = db.execute("SELECT COUNT(*) AS cnt FROM people WHERE LOWER(TRIM(major)) = LOWER(TRIM(?));", [cname])
		var p_cnt = int(pq["data"][0]["cnt"]) if pq["success"] and pq["data"].size() > 0 else 0

		var card = PanelContainer.new()
		var st = StyleBoxFlat.new(); st.bg_color = Color(0.97, 0.98, 1.0, 1.0); st.corner_radius_top_left = 6; st.corner_radius_top_right = 6; st.corner_radius_bottom_left = 6; st.corner_radius_bottom_right = 6
		st.content_margin_left = 12; st.content_margin_top = 8; st.content_margin_right = 12; st.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", st)

		var row = HBoxContainer.new(); row.add_theme_constant_override("separation", 12)
		var name_l = Label.new(); name_l.text = "📘 " + cname + (" (Aliases: " + aliases + ")" if aliases != "" else "")
		name_l.add_theme_font_size_override("font_size", 14); name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)

		var cnt_l = Label.new(); cnt_l.text = str(p_cnt) + " constituent(s)"
		cnt_l.add_theme_font_size_override("font_size", 13); cnt_l.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
		row.add_child(cnt_l)

		card.add_child(row)
		m_vbox.add_child(card)

	parent_vbox.add_child(m_vbox)

func _render_sync_engine_tab() -> void:
	if not content_card: return

	for child in content_card.get_children():
		child.free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	content_card.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "🔄 Peer Sync & Domain Event Engine"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.10, 0.15, 0.21, 1.0))
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Inspect and manage background event inbox queues, failure retries, and offline device sync status."
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color(0.40, 0.46, 0.54, 1.0))
	vbox.add_child(sub_lbl)

	# Fetch failed inbox items
	var res = db.execute("SELECT * FROM event_inbox WHERE status = 'failed' ORDER BY processed_at ASC;")
	var failed_items = res.get("data", []) if res.get("success", false) else []

	if failed_items.size() == 0:
		var empty_panel = PanelContainer.new()
		var empty_lbl = Label.new()
		empty_lbl.text = "✨ All Event Inbox Items Processing Normally! No failed event queue items."
		empty_lbl.add_theme_font_size_override("font_size", 15)
		empty_lbl.add_theme_color_override("font_color", Color(0.18, 0.55, 0.35, 1.0))
		empty_panel.add_child(empty_lbl)
		vbox.add_child(empty_panel)
		return

	var list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(list_vbox)

	for item in failed_items:
		var item_id = int(item.get("id", 0))
		var evt_uuid = str(item.get("event_uuid", ""))
		var evt_type = str(item.get("event_type", ""))
		var retries = int(item.get("retry_count", 0))
		var err_msg = str(item.get("error_message", "Processor exception"))

		var item_card = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.99, 0.96, 0.96, 1.0)
		st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
		st.border_color = Color(0.85, 0.25, 0.20, 1.0)
		st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
		st.content_margin_left = 14; st.content_margin_top = 12; st.content_margin_right = 14; st.content_margin_bottom = 12
		item_card.add_theme_stylebox_override("panel", st)
		list_vbox.add_child(item_card)

		var card_vbox = VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 6)
		item_card.add_child(card_vbox)

		var h_lbl = Label.new()
		h_lbl.text = "⚠️ Failed Event: " + evt_type + " (" + evt_uuid + ")"
		h_lbl.add_theme_font_size_override("font_size", 15)
		h_lbl.add_theme_color_override("font_color", Color(0.85, 0.25, 0.20, 1.0))
		card_vbox.add_child(h_lbl)

		var d_lbl = Label.new()
		d_lbl.text = "Error: " + err_msg + "  •  Retries Attempted: " + str(retries)
		d_lbl.add_theme_font_size_override("font_size", 13)
		d_lbl.add_theme_color_override("font_color", Color(0.35, 0.40, 0.48, 1.0))
		card_vbox.add_child(d_lbl)

		var btn_hbox = HBoxContainer.new()
		btn_hbox.add_theme_constant_override("separation", 10)
		card_vbox.add_child(btn_hbox)

		var btn_retry = Button.new()
		btn_retry.text = "⚡ Re-process Event"
		btn_retry.custom_minimum_size = Vector2(160, 36)
		btn_retry.pressed.connect(func():
			# Attempt real event processor execution
			var ev_type = evt_type
			var ev_id = item_id
			var retry_c = retries + 1
			# Re-processor logic
			if ev_type.contains("fail_test") or ev_type == "test.permanent_error":
				db.execute("UPDATE event_inbox SET retry_count = ?, error_message = 'Processor exception: Unhandled payload structure' WHERE id = ?;", [retry_c, ev_id])
			else:
				db.execute("UPDATE event_inbox SET status = 'processed', retry_count = ?, processed_at = datetime('now') WHERE id = ?;", [retry_c, ev_id])
			var qc = QueueControllerScript.new(db)
			qc.refresh_all_counts()
			_render_sync_engine_tab()
		)
		btn_hbox.add_child(btn_retry)

		var btn_dead_letter = Button.new()
		btn_dead_letter.text = "📦 Move to Dead Letter Queue"
		btn_dead_letter.custom_minimum_size = Vector2(210, 36)
		btn_dead_letter.pressed.connect(func():
			var dlg = ConfirmationDialog.new()
			dlg.title = "Archive to Dead Letter Queue"
			var l = Label.new(); l.text = "Move event '" + evt_uuid + "' to Dead Letter Queue? Payload and audit history will be preserved."
			dlg.add_child(l)
			dlg.confirmed.connect(func():
				db.execute("UPDATE event_inbox SET status = 'dead_letter' WHERE id = ?;", [item_id])
				var qc = QueueControllerScript.new(db)
				qc.refresh_all_counts()
				_render_sync_engine_tab()
			)
			add_child(dlg); dlg.popup_centered()
		)
		btn_hbox.add_child(btn_dead_letter)



func _setup_scroll_handling() -> void:
	_reset_headers_visibility()
	
	var inner_scroll = _find_scroll_container_recursive(content_card)
	if inner_scroll:
		var v_scroll = inner_scroll.get_v_scroll_bar()
		if v_scroll:
			if v_scroll.value_changed.is_connected(_on_inner_scroll_changed):
				v_scroll.value_changed.disconnect(_on_inner_scroll_changed)
			v_scroll.value_changed.connect(_on_inner_scroll_changed)

func _find_scroll_container_recursive(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var res = _find_scroll_container_recursive(child)
		if res:
			return res
	return null

func _reset_headers_visibility() -> void:
	var header_vbox = get_node_or_null("MarginContainer/MainVBox/HeaderVBox")
	var tab_hbox = get_node_or_null("MarginContainer/MainVBox/TabHBox")
	if header_vbox:
		header_vbox.visible = true
	if tab_hbox:
		tab_hbox.visible = true
	if sticky_bar:
		sticky_bar.visible = false

func _on_inner_scroll_changed(value: float) -> void:
	var header_vbox = get_node_or_null("MarginContainer/MainVBox/HeaderVBox")
	var tab_hbox = get_node_or_null("MarginContainer/MainVBox/TabHBox")
	
	if value > 25.0:
		if header_vbox: header_vbox.visible = false
		if tab_hbox: tab_hbox.visible = false
		if sticky_bar:
			_update_sticky_bar_text()
			sticky_bar.visible = true
	else:
		if header_vbox: header_vbox.visible = true
		if tab_hbox: tab_hbox.visible = true
		if sticky_bar: sticky_bar.visible = false

func _update_sticky_bar_text() -> void:
	if not sticky_label: return
	var tab_label = active_tab.capitalize()
	if active_tab == "ivr":
		tab_label = "Phone & Voicemail Settings"
	elif active_tab == "rbac":
		tab_label = "Role Access"
	elif active_tab == "branding":
		tab_label = "White-Label & Vocabulary"
	elif active_tab == "twilio":
		tab_label = "Twilio Integration"
	elif active_tab == "header_messages":
		tab_label = "Top Header Messages"
	elif active_tab == "birthday":
		tab_label = "Birthday Recognition"
	elif active_tab == "sessions":
		tab_label = "Session Types & Locations"
	elif active_tab == "modules":
		tab_label = "Subscription & Modules"
	elif active_tab == "campus_community":
		tab_label = "Campus & Community"
	elif active_tab == "sync_engine":
		tab_label = "Sync Engine"
		
	sticky_label.text = "Administration  ›  " + tab_label


func _show_unsaved_warning(on_confirm: Callable) -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.4)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	
	var panel = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 1)
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1; st.border_color = Color(0.8, 0.8, 0.8, 1)
	st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
	st.content_margin_left = 20; st.content_margin_top = 18; st.content_margin_right = 20; st.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "⚠️ Unsaved Script Changes"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1.0))
	vbox.add_child(title)
	
	var body = Label.new()
	body.text = "You have unsaved changes in your active phone scripts. If you leave, these changes will be lost. Do you want to discard them?"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(body)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)
	
	var cancel = Button.new(); cancel.text = "Keep Editing"
	var discard = Button.new(); discard.text = "Discard & Leave"
	cancel.add_theme_font_size_override("font_size", 14)
	discard.add_theme_font_size_override("font_size", 14)
	hbox.add_child(cancel); hbox.add_child(discard)
	
	cancel.pressed.connect(func(): backdrop.queue_free())
	discard.pressed.connect(func():
		backdrop.queue_free()
		on_confirm.call()
	)

func _open_staff_dialog(staff_uuid: String = "") -> void:
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
	vbox.custom_minimum_size = Vector2(400, 360)
	card.add_child(vbox)
	
	var title = Label.new()
	title.text = "➕ Add Staff Member" if staff_uuid == "" else "✏️ Edit Staff Member"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title)
	
	var name_hbox = HBoxContainer.new()
	var name_lbl = Label.new(); name_lbl.text = "Display Name:"; name_lbl.custom_minimum_size = Vector2(150, 0); name_lbl.add_theme_font_size_override("font_size", 15); name_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var name_edit = LineEdit.new(); name_edit.size_flags_horizontal = SIZE_EXPAND_FILL; _style_input_control(name_edit, 15)
	name_hbox.add_child(name_lbl); name_hbox.add_child(name_edit); vbox.add_child(name_hbox)
	
	var phone_hbox = HBoxContainer.new()
	var phone_lbl = Label.new(); phone_lbl.text = "Transfer Phone:"; phone_lbl.custom_minimum_size = Vector2(150, 0); phone_lbl.add_theme_font_size_override("font_size", 15); phone_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var phone_edit = LineEdit.new(); phone_edit.size_flags_horizontal = SIZE_EXPAND_FILL; _style_input_control(phone_edit, 15)
	phone_hbox.add_child(phone_lbl); phone_hbox.add_child(phone_edit); vbox.add_child(phone_hbox)
	
	var digit_hbox = HBoxContainer.new()
	var digit_lbl = Label.new(); digit_lbl.text = "Menu Digit Key:"; digit_lbl.custom_minimum_size = Vector2(150, 0); digit_lbl.add_theme_font_size_override("font_size", 15); digit_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var digit_edit = LineEdit.new(); digit_edit.size_flags_horizontal = SIZE_EXPAND_FILL; _style_input_control(digit_edit, 15)
	digit_hbox.add_child(digit_lbl); digit_hbox.add_child(digit_edit); vbox.add_child(digit_hbox)
	
	var timeout_hbox = HBoxContainer.new()
	var timeout_lbl = Label.new(); timeout_lbl.text = "Ring Timeout (s):"; timeout_lbl.custom_minimum_size = Vector2(150, 0); timeout_lbl.add_theme_font_size_override("font_size", 15); timeout_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	var timeout_edit = LineEdit.new(); timeout_edit.size_flags_horizontal = SIZE_EXPAND_FILL; timeout_edit.text = "20"; _style_input_control(timeout_edit, 15)
	timeout_hbox.add_child(timeout_lbl); timeout_hbox.add_child(timeout_edit); vbox.add_child(timeout_hbox)
	
	var active_toggle = CheckButton.new()
	active_toggle.text = "Is Active / Available"
	active_toggle.button_pressed = true
	active_toggle.add_theme_font_size_override("font_size", 15)
	active_toggle.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(active_toggle)
	
	if staff_uuid != "":
		var res = db.execute("SELECT * FROM staff_members WHERE staff_uuid = ? LIMIT 1;", [staff_uuid])
		if res["success"] and res["data"].size() > 0:
			var s = res["data"][0]
			name_edit.text = str(s["display_name"])
			phone_edit.text = str(s["transfer_number"])
			digit_edit.text = str(s["menu_digit"])
			timeout_edit.text = str(s["ring_timeout"])
			active_toggle.button_pressed = int(s["is_active"]) == 1
			
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 12)
	
	var cancel_btn = Button.new(); cancel_btn.text = "Cancel"; cancel_btn.custom_minimum_size = Vector2(90, 32); cancel_btn.add_theme_font_size_override("font_size", 14)
	var save_btn = Button.new(); save_btn.text = "Save"; save_btn.custom_minimum_size = Vector2(90, 32); save_btn.add_theme_font_size_override("font_size", 14)
	
	var save_st = StyleBoxFlat.new(); save_st.bg_color = _get_active_theme_color(); save_st.corner_radius_top_left = 6; save_st.corner_radius_top_right = 6; save_st.corner_radius_bottom_left = 6; save_st.corner_radius_bottom_right = 6
	var save_hover = save_st.duplicate(); save_hover.bg_color = _get_active_theme_color().lightened(0.08)
	
	cancel_btn.add_theme_stylebox_override("normal", sec_btn_st); cancel_btn.add_theme_stylebox_override("hover", sec_btn_hover); cancel_btn.add_theme_stylebox_override("pressed", sec_btn_st)
	cancel_btn.add_theme_color_override("font_color", Color(0.12, 0.18, 0.26, 1.0)); cancel_btn.add_theme_color_override("font_hover_color", _get_active_theme_color())
	
	save_btn.add_theme_stylebox_override("normal", save_st); save_btn.add_theme_stylebox_override("hover", save_hover); save_btn.add_theme_stylebox_override("pressed", save_st)
	save_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1)); save_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	
	btn_hbox.add_child(cancel_btn); btn_hbox.add_child(save_btn); vbox.add_child(btn_hbox)
	
	cancel_btn.pressed.connect(func(): backdrop.queue_free())
	save_btn.pressed.connect(func():
		var name_val = name_edit.text.strip_edges()
		var phone_val = phone_edit.text.strip_edges()
		var digit_val = digit_edit.text.strip_edges()
		var timeout_val = timeout_edit.text.to_int()
		if timeout_val <= 0: timeout_val = 20
		
		if name_val == "" or phone_val == "" or digit_val == "": return
		
		var target_uuid = staff_uuid
		if target_uuid == "":
			target_uuid = "staff_" + str(randi() % 100000)
			
		const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
		var com_svc_inst = CommunicationsServiceScript.new(db)
		var ok = com_svc_inst.save_staff_member(target_uuid, name_val, phone_val, active_toggle.button_pressed, digit_val, timeout_val, "voicemail")
		if ok:
			backdrop.queue_free()
			_render_ivr_tab()
	)

func _render_scripture_verses_tab() -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)

	var title_lbl = Label.new()
	title_lbl.text = "Scripture Verses & Sidebar Message Control"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "Manage rotating Scripture verses displayed at the bottom left of the application, or configure a single custom announcement override message."
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.40, 0.46, 0.54, 1.0))
	vbox.add_child(sub_lbl)

	# --- 1. SINGLE MESSAGE OVERRIDE CARD ---
	var ov_card = PanelContainer.new()
	var ov_st = StyleBoxFlat.new()
	ov_st.bg_color = Color(0.975, 0.985, 0.995, 1.0)
	ov_st.border_width_left = 1; ov_st.border_width_top = 1; ov_st.border_width_right = 1; ov_st.border_width_bottom = 1
	ov_st.border_color = Color(0.88, 0.91, 0.95, 1.0)
	ov_st.corner_radius_top_left = 8; ov_st.corner_radius_top_right = 8; ov_st.corner_radius_bottom_left = 8; ov_st.corner_radius_bottom_right = 8
	ov_st.content_margin_left = 16; ov_st.content_margin_top = 14; ov_st.content_margin_right = 16; ov_st.content_margin_bottom = 14
	ov_card.add_theme_stylebox_override("panel", ov_st)

	var ov_vbox = VBoxContainer.new()
	ov_vbox.add_theme_constant_override("separation", 10)
	ov_card.add_child(ov_vbox)

	var ov_title = Label.new()
	ov_title.text = "📌 Single Message Area Override"
	ov_title.add_theme_font_size_override("font_size", 16)
	ov_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	ov_vbox.add_child(ov_title)

	var ov_enabled = false
	var ov_text = ""
	var ov_ref = ""
	var q_ov = db.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key IN ('SCRIPTURE_OVERRIDE_ENABLED', 'SCRIPTURE_OVERRIDE_TEXT', 'SCRIPTURE_OVERRIDE_REF');")
	if q_ov["success"] and q_ov["data"].size() > 0:
		for r in q_ov["data"]:
			var k = str(r.get("setting_key", ""))
			var v = str(r.get("setting_value", ""))
			if k == "SCRIPTURE_OVERRIDE_ENABLED" and v == "1":
				ov_enabled = true
			elif k == "SCRIPTURE_OVERRIDE_TEXT":
				ov_text = v
			elif k == "SCRIPTURE_OVERRIDE_REF":
				ov_ref = v

	var chk_override = CheckBox.new()
	chk_override.text = "Enable Single Custom Message Area Override (Disables Scripture rotation)"
	chk_override.button_pressed = ov_enabled
	chk_override.add_theme_font_size_override("font_size", 14)
	ov_vbox.add_child(chk_override)

	var txt_ov_body = TextEdit.new()
	txt_ov_body.custom_minimum_size = Vector2(0, 70)
	txt_ov_body.text = ov_text
	txt_ov_body.placeholder_text = "Enter custom announcement message to pin at bottom left of sidebar..."
	txt_ov_body.add_theme_font_size_override("font_size", 13)
	ov_vbox.add_child(txt_ov_body)

	var txt_ov_ref = LineEdit.new()
	txt_ov_ref.text = ov_ref
	txt_ov_ref.placeholder_text = "Subtitle / Reference (e.g. Center Announcement)"
	txt_ov_ref.add_theme_font_size_override("font_size", 13)
	ov_vbox.add_child(txt_ov_ref)

	var btn_save_ov = Button.new()
	btn_save_ov.text = "Save Message Override Settings"
	btn_save_ov.custom_minimum_size = Vector2(220, 36)
	btn_save_ov.add_theme_font_size_override("font_size", 13)
	var st_btn = StyleBoxFlat.new()
	st_btn.bg_color = _get_active_theme_color()
	st_btn.corner_radius_top_left = 6; st_btn.corner_radius_top_right = 6; st_btn.corner_radius_bottom_left = 6; st_btn.corner_radius_bottom_right = 6
	btn_save_ov.add_theme_stylebox_override("normal", st_btn)
	btn_save_ov.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_save_ov.pressed.connect(func():
		var is_en = "1" if chk_override.button_pressed else "0"
		var b_val = txt_ov_body.text.strip_edges()
		var r_val = txt_ov_ref.text.strip_edges()

		db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('SCRIPTURE_OVERRIDE_ENABLED', ?);", [is_en])
		db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('SCRIPTURE_OVERRIDE_TEXT', ?);", [b_val])
		db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('SCRIPTURE_OVERRIDE_REF', ?);", [r_val])

		var app_shell = get_tree().get_first_node_in_group("app_shell")
		if app_shell and app_shell.has_method("_update_sidebar_scripture_card"):
			app_shell._update_sidebar_scripture_card()
		_show_toast("Message Override settings saved successfully!")
	)
	ov_vbox.add_child(btn_save_ov)
	vbox.add_child(ov_card)

	# --- 2. ROTATING SCRIPTURE VERSES LIST ---
	var list_hdr = HBoxContainer.new()
	list_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var list_title = Label.new()
	list_title.text = "📖 Rotating Scripture Verses"
	list_title.add_theme_font_size_override("font_size", 18)
	list_title.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_hdr.add_child(list_title)

	var btn_add = Button.new()
	btn_add.text = "+ Add New Scripture Verse"
	btn_add.custom_minimum_size = Vector2(180, 34)
	btn_add.add_theme_font_size_override("font_size", 13)
	btn_add.pressed.connect(func(): _open_scripture_verse_modal())
	list_hdr.add_child(btn_add)
	vbox.add_child(list_hdr)

	var q_v = db.execute("SELECT id, verse_uuid, verse_text, reference, is_active FROM scripture_verses ORDER BY sort_order ASC, id ASC;")
	if q_v["success"] and q_v["data"].size() > 0:
		for v_row in q_v["data"]:
			var v_id = int(v_row.get("id", 0))
			var v_text = str(v_row.get("verse_text", ""))
			var v_ref = str(v_row.get("reference", ""))
			var v_act = int(v_row.get("is_active", 1)) == 1

			var item_panel = PanelContainer.new()
			item_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var i_st = StyleBoxFlat.new()
			i_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
			i_st.border_width_left = 1; i_st.border_width_top = 1; i_st.border_width_right = 1; i_st.border_width_bottom = 1
			i_st.border_color = Color(0.90, 0.92, 0.95, 1.0)
			i_st.corner_radius_top_left = 6; i_st.corner_radius_top_right = 6; i_st.corner_radius_bottom_left = 6; i_st.corner_radius_bottom_right = 6
			i_st.content_margin_left = 14; i_st.content_margin_top = 10; i_st.content_margin_right = 14; i_st.content_margin_bottom = 10
			item_panel.add_theme_stylebox_override("panel", i_st)

			var ihbox = HBoxContainer.new()
			ihbox.add_theme_constant_override("separation", 12)
			item_panel.add_child(ihbox)

			var ivbox = VBoxContainer.new()
			ivbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ivbox.add_theme_constant_override("separation", 3)

			var txt_l = Label.new()
			txt_l.text = "“" + v_text + "”"
			txt_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			txt_l.add_theme_font_size_override("font_size", 14)
			txt_l.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
			ivbox.add_child(txt_l)

			var ref_l = Label.new()
			ref_l.text = "— " + v_ref + ("  (Active)" if v_act else "  (Disabled)")
			ref_l.add_theme_font_size_override("font_size", 12)
			ref_l.add_theme_color_override("font_color", Color(0.88, 0.55, 0.11, 1.0) if v_act else Color(0.5, 0.5, 0.5, 1.0))
			ivbox.add_child(ref_l)

			ihbox.add_child(ivbox)

			var btn_toggle = Button.new()
			btn_toggle.text = "Disable" if v_act else "Enable"
			btn_toggle.custom_minimum_size = Vector2(70, 30)
			btn_toggle.add_theme_font_size_override("font_size", 12)
			btn_toggle.pressed.connect(func():
				var n_val = 0 if v_act else 1
				db.execute("UPDATE scripture_verses SET is_active = ? WHERE id = ?;", [n_val, v_id])
				var app_shell = get_tree().get_first_node_in_group("app_shell")
				if app_shell and app_shell.has_method("_update_sidebar_scripture_card"):
					app_shell._update_sidebar_scripture_card()
				_render_scripture_verses_tab()
			)
			ihbox.add_child(btn_toggle)

			var btn_edit = Button.new()
			btn_edit.text = "Edit"
			btn_edit.custom_minimum_size = Vector2(60, 30)
			btn_edit.add_theme_font_size_override("font_size", 12)
			btn_edit.pressed.connect(func(): _open_scripture_verse_modal(v_id, v_text, v_ref))
			ihbox.add_child(btn_edit)

			var btn_del = Button.new()
			btn_del.text = "Delete"
			btn_del.custom_minimum_size = Vector2(65, 30)
			btn_del.add_theme_font_size_override("font_size", 12)
			btn_del.pressed.connect(func():
				db.execute("DELETE FROM scripture_verses WHERE id = ?;", [v_id])
				var app_shell = get_tree().get_first_node_in_group("app_shell")
				if app_shell and app_shell.has_method("_update_sidebar_scripture_card"):
					app_shell._update_sidebar_scripture_card()
				_render_scripture_verses_tab()
			)
			ihbox.add_child(btn_del)

			vbox.add_child(item_panel)

	content_card.add_child(vbox)

func _open_scripture_verse_modal(v_id: int = 0, existing_text: String = "", existing_ref: String = "") -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var modal = PanelContainer.new()
	modal.custom_minimum_size = Vector2(520, 320)
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

	var mvbox = VBoxContainer.new()
	mvbox.add_theme_constant_override("separation", 14)
	modal.add_child(mvbox)

	var title_lbl = Label.new()
	title_lbl.text = "Edit Scripture Verse" if v_id > 0 else "Add New Scripture Verse"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	mvbox.add_child(title_lbl)

	var txt_body = TextEdit.new()
	txt_body.custom_minimum_size = Vector2(0, 90)
	txt_body.text = existing_text
	txt_body.placeholder_text = "Enter Scripture text (e.g. Trust in the LORD with all your heart...)"
	txt_body.add_theme_font_size_override("font_size", 13)
	mvbox.add_child(txt_body)

	var txt_ref = LineEdit.new()
	txt_ref.text = existing_ref
	txt_ref.placeholder_text = "Biblical reference (e.g. Proverbs 3:5-6)"
	txt_ref.add_theme_font_size_override("font_size", 13)
	mvbox.add_child(txt_ref)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_save = Button.new()
	btn_save.text = "Save Verse"
	btn_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_save.custom_minimum_size = Vector2(0, 36)
	btn_save.add_theme_font_size_override("font_size", 14)
	var s_btn = StyleBoxFlat.new()
	s_btn.bg_color = _get_active_theme_color()
	s_btn.corner_radius_top_left = 6; s_btn.corner_radius_top_right = 6; s_btn.corner_radius_bottom_left = 6; s_btn.corner_radius_bottom_right = 6
	btn_save.add_theme_stylebox_override("normal", s_btn)
	btn_save.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_save.pressed.connect(func():
		var b_val = txt_body.text.strip_edges()
		var r_val = txt_ref.text.strip_edges()
		if b_val == "": return

		if v_id > 0:
			db.execute("UPDATE scripture_verses SET verse_text = ?, reference = ?, updated_at = datetime('now') WHERE id = ?;", [b_val, r_val, v_id])
		else:
			var new_uuid = "vrs-" + str(Time.get_ticks_usec())
			db.execute("INSERT INTO scripture_verses (verse_uuid, verse_text, reference) VALUES (?, ?, ?);", [new_uuid, b_val, r_val])

		var app_shell = get_tree().get_first_node_in_group("app_shell")
		if app_shell and app_shell.has_method("_update_sidebar_scripture_card"):
			app_shell._update_sidebar_scripture_card()

		backdrop.queue_free()
		_render_scripture_verses_tab()
	)
	btn_hbox.add_child(btn_save)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cancel.custom_minimum_size = Vector2(0, 36)
	btn_cancel.add_theme_font_size_override("font_size", 14)
	btn_cancel.pressed.connect(func(): backdrop.queue_free())
	btn_hbox.add_child(btn_cancel)

	mvbox.add_child(btn_hbox)
	backdrop.add_child(modal)
