extends "res://app/scenes/standard_page_container.gd"

## Discipleship Pathways Controller (Real Life, Fellows, LEAD)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PathwaysServiceScript = preload("res://src/domain/pathways/pathways_service.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			pw_service = PathwaysServiceScript.new(db)
			_populate_dropdowns()
			_refresh_roster()

var pw_service: RefCounted
var person_list: Array = []

@onready var person_dropdown: OptionButton = %PersonDropdown
@onready var chk_real_life: CheckBox = %ChkRealLife
@onready var chk_fellows: CheckBox = %ChkFellows
@onready var chk_fellows_cert: CheckBox = %ChkFellowsCert
@onready var chk_lead: CheckBox = %ChkLead
@onready var chk_lead_cert: CheckBox = %ChkLeadCert
@onready var lead_year_dropdown: OptionButton = %LeadYearDropdown
@onready var btn_save_pathway: Button = %BtnSavePathway
@onready var roster_card: PanelContainer = %RosterCard

func _ready() -> void:
	_init_database()
	_style_card()
	_populate_dropdowns()
	_connect_signals()
	_refresh_roster()

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig = MigrationsRunnerScript.new(db)
		mig.run_migrations()
	if not pw_service:
		pw_service = PathwaysServiceScript.new(db)

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
	roster_card.add_theme_stylebox_override("panel", style)

	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = _get_active_theme_color()
	btn_st.corner_radius_top_left = 6
	btn_st.corner_radius_top_right = 6
	btn_st.corner_radius_bottom_left = 6
	btn_st.corner_radius_bottom_right = 6
	btn_save_pathway.add_theme_stylebox_override("normal", btn_st)
	btn_save_pathway.add_theme_stylebox_override("hover", btn_st)
	btn_save_pathway.add_theme_stylebox_override("pressed", btn_st)

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
	if not pw_service: pw_service = PathwaysServiceScript.new(db)

	person_dropdown.clear()
	var p_res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name FROM people ORDER BY last_name ASC, first_name ASC;")
	if p_res["success"] and p_res["data"].size() > 0:
		person_list = p_res["data"]
		for i in range(person_list.size()):
			var p = person_list[i]
			var fn = str(p.get("first_name")) if p.get("first_name") != null else ""
			var ln = str(p.get("last_name")) if p.get("last_name") != null else ""
			var name = (fn + " " + ln).strip_edges() + " (" + str(p.get("human_id")) + ")"
			person_dropdown.add_item(name, i)

	lead_year_dropdown.clear()
	lead_year_dropdown.add_item("Year 1", 0)
	lead_year_dropdown.add_item("Year 2", 1)
	lead_year_dropdown.add_item("Graduated", 2)

	_on_person_selected(0)

func _connect_signals() -> void:
	if btn_save_pathway: btn_save_pathway.pressed.connect(_on_save_pathway_pressed)
	if person_dropdown: person_dropdown.item_selected.connect(_on_person_selected)

func _on_person_selected(index: int) -> void:
	if index < 0 or index >= person_list.size(): return
	var p_id = int(person_list[index].get("id", 0))
	var p_info = pw_service.get_person_legacy_pathway(p_id)

	chk_real_life.button_pressed = (int(p_info.get("real_life_enrolled", 0)) == 1)
	chk_fellows.button_pressed = (int(p_info.get("fellows_enrolled", 0)) == 1)
	chk_fellows_cert.button_pressed = (int(p_info.get("fellows_certificate", 0)) == 1)
	chk_lead.button_pressed = (int(p_info.get("lead_enrolled", 0)) == 1)
	chk_lead_cert.button_pressed = (int(p_info.get("lead_certificate", 0)) == 1)

	var yr = str(p_info.get("lead_current_year", "Year 1"))
	if yr == "Year 2": lead_year_dropdown.select(1)
	elif yr == "Graduated": lead_year_dropdown.select(2)
	else: lead_year_dropdown.select(0)

func _on_save_pathway_pressed() -> void:
	if person_list.size() == 0: return
	var sel_idx = person_dropdown.selected
	if sel_idx < 0 or sel_idx >= person_list.size(): return

	var person = person_list[sel_idx]
	var lead_yr = lead_year_dropdown.get_item_text(lead_year_dropdown.selected)

	var p_data = {
		"real_life_enrolled": 1 if chk_real_life.button_pressed else 0,
		"fellows_enrolled": 1 if chk_fellows.button_pressed else 0,
		"fellows_certificate": 1 if chk_fellows_cert.button_pressed else 0,
		"fellows_completions": "[\"Year 1 Core\", \"Foundations\"]",
		"lead_enrolled": 1 if chk_lead.button_pressed else 0,
		"lead_certificate": 1 if chk_lead_cert.button_pressed else 0,
		"lead_current_year": lead_yr
	}

	var res = pw_service.save_legacy_pathway_atomic(person, p_data)
	if res["success"]:
		print("Saved legacy pathway tracks for constituent: ", person.get("human_id"))
		_refresh_roster()

func _refresh_roster() -> void:
	if not db: return
	if not pw_service: pw_service = PathwaysServiceScript.new(db)

	for child in roster_card.get_children(): child.free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title_lbl = Label.new()
	title_lbl.text = "Discipleship Pathway Roster & Legacy Tracks Matrix"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_lbl)

	var roster = pw_service.get_all_pathway_roster()
	if roster.size() > 0:
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 360)
		scroll.size_flags_vertical = SIZE_EXPAND_FILL

		var list_vbox = VBoxContainer.new()
		list_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		list_vbox.add_theme_constant_override("separation", 8)

		for item in roster:
			var fn = str(item.get("first_name")) if item.get("first_name") != null else ""
			var ln = str(item.get("last_name")) if item.get("last_name") != null else ""
			var name = (fn + " " + ln).strip_edges()
			if name == "": name = str(item.get("human_id"))

			var tracks = []
			if int(item.get("real_life_enrolled", 0)) == 1: tracks.append("🌱 Real Life")
			if int(item.get("fellows_enrolled", 0)) == 1:
				var cert = " 📜" if int(item.get("fellows_certificate", 0)) == 1 else ""
				tracks.append("🎓 Fellows" + cert)
			if int(item.get("lead_enrolled", 0)) == 1:
				var cert = " 📜" if int(item.get("lead_certificate", 0)) == 1 else ""
				var yr = str(item.get("lead_current_year", "Year 1"))
				tracks.append("⚡ LEAD (" + yr + cert + ")")

			var track_str = ", ".join(tracks) if tracks.size() > 0 else "None"

			var row = Label.new()
			row.text = "  📈 " + name + " • Active Tracks: " + track_str
			row.add_theme_font_size_override("font_size", 13)
			row.add_theme_color_override("font_color", Color(0.22, 0.28, 0.36, 1.0))
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list_vbox.add_child(row)

		scroll.add_child(list_vbox)
		vbox.add_child(scroll)
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "No constituents found in directory."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(empty_lbl)

	roster_card.add_child(vbox)
