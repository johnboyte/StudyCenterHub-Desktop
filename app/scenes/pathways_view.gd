extends "res://app/scenes/standard_page_container.gd"

## Modern Annual Pathways Management View (Stage 2)
## Manages Fellows and LEAD Annual Programs, Rosters, Requirements, and Linked Sessions.
## Preserves legacy pathways matrix as a temporary fallback.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PathwaysServiceScript = preload("res://src/domain/pathways/pathways_service.gd")
const UnifiedPathwaysServiceScript = preload("res://src/domain/pathways/unified_pathways_service.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			pw_legacy_service = PathwaysServiceScript.new(db)
			pw_unified_service = UnifiedPathwaysServiceScript.new(db)
			_load_context_data()

var pw_legacy_service: RefCounted
var pw_unified_service: RefCounted

# Context State
var current_pathway_key: String = "fellows"
var current_academic_year: String = "2026-2027"
var current_program: Dictionary = {}
var current_tab: String = "participants" # participants, requirements, sessions
var is_legacy_fallback_open: bool = false

# UI References
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var btn_legacy_fallback: Button = %BtnLegacyFallback

@onready var year_dropdown: OptionButton = %YearDropdown
@onready var btn_pathway_fellows: Button = %BtnPathwayFellows
@onready var btn_pathway_lead: Button = %BtnPathwayLead
@onready var btn_create_program: Button = %BtnCreateProgram

# Summary Cards
@onready var stat_card_total: PanelContainer = %StatCardTotal
@onready var stat_lbl_total: Label = %StatLblTotal
@onready var stat_card_tracks: PanelContainer = %StatCardTracks
@onready var stat_lbl_tracks: Label = %StatLblTracks
@onready var stat_card_standings: PanelContainer = %StatCardStandings
@onready var stat_lbl_standings: Label = %StatLblStandings
@onready var stat_card_reqs: PanelContainer = %StatCardReqs
@onready var stat_lbl_reqs: Label = %StatLblReqs

# Tab Navigation Buttons
@onready var btn_tab_participants: Button = %BtnTabParticipants
@onready var btn_tab_requirements: Button = %BtnTabRequirements
@onready var btn_tab_sessions: Button = %BtnTabSessions
@onready var btn_tab_migration: Button = %BtnTabMigration

# Tab Containers
@onready var participants_panel: VBoxContainer = %ParticipantsPanel
@onready var requirements_panel: VBoxContainer = %RequirementsPanel
@onready var sessions_panel: VBoxContainer = %SessionsPanel
@onready var migration_panel: VBoxContainer = %MigrationPanel

# Migration Review Controls
@onready var btn_import_staging: Button = %BtnImportStaging
@onready var btn_dry_run_audit: Button = %BtnDryRunAudit
@onready var staging_summary_lbl: Label = %StagingSummaryLbl
@onready var staging_list_vbox: VBoxContainer = %StagingListVBox
@onready var staging_empty_lbl: Label = %StagingEmptyLbl

# Roster Controls
@onready var roster_search_box: LineEdit = %RosterSearchBox
@onready var roster_track_filter: OptionButton = %RosterTrackFilter
@onready var roster_standing_filter: OptionButton = %RosterStandingFilter
@onready var btn_export_roster_csv: Button = %BtnExportRosterCsv
@onready var btn_add_participant: Button = %BtnAddParticipant
@onready var roster_list_vbox: VBoxContainer = %RosterListVBox
@onready var roster_empty_lbl: Label = %RosterEmptyLbl

# Requirements Controls
@onready var btn_create_requirement: Button = %BtnCreateRequirement
@onready var reqs_list_vbox: VBoxContainer = %ReqsListVBox
@onready var reqs_empty_lbl: Label = %ReqsEmptyLbl

# Linked Sessions Controls
@onready var btn_link_session: Button = %BtnLinkSession
@onready var sessions_list_vbox: VBoxContainer = %SessionsListVBox
@onready var sessions_empty_lbl: Label = %SessionsEmptyLbl

# Legacy Card Container
@onready var legacy_container: VBoxContainer = %LegacyContainer
@onready var person_dropdown: OptionButton = %PersonDropdown
@onready var chk_real_life: CheckBox = %ChkRealLife
@onready var chk_fellows: CheckBox = %ChkFellows
@onready var chk_fellows_cert: CheckBox = %ChkFellowsCert
@onready var chk_lead: CheckBox = %ChkLead
@onready var chk_lead_cert: CheckBox = %ChkLeadCert
@onready var lead_year_dropdown: OptionButton = %LeadYearDropdown
@onready var btn_save_pathway: Button = %BtnSavePathway
@onready var roster_card: PanelContainer = %RosterCard

var person_list: Array = []

func _ready() -> void:
	_init_database()
	_setup_styles()
	_connect_signals()
	_load_context_data()

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig = MigrationsRunnerScript.new(db)
		mig.run_migrations()
	if not pw_legacy_service:
		pw_legacy_service = PathwaysServiceScript.new(db)
	if not pw_unified_service:
		pw_unified_service = UnifiedPathwaysServiceScript.new(db)

func _setup_styles() -> void:
	var accent = _get_active_theme_color()

	# Modern header style
	title_label.text = "Discipleship Pathways Management"
	subtitle_label.text = "Manage annual Fellows & LEAD formation programs, rosters, checklist requirements, and linked sessions."

	if btn_legacy_fallback: btn_legacy_fallback.visible = false
	if legacy_container: legacy_container.visible = false
	_style_button(btn_create_program, accent, Color.WHITE)
	_style_button(btn_add_participant, accent, Color.WHITE)
	_style_button(btn_create_requirement, accent, Color.WHITE)
	_style_button(btn_link_session, accent, Color.WHITE)

	_update_pathway_toggle_buttons()
	_update_tab_buttons()

func _style_checkbox(chk: CheckBox, text_color: Color = Color(0.12, 0.16, 0.24, 1.0)) -> void:
	if not chk: return
	chk.add_theme_color_override("font_color", text_color)
	chk.add_theme_color_override("font_hover_color", Color(0.08, 0.35, 0.70, 1.0))
	chk.add_theme_color_override("font_pressed_color", text_color)
	chk.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.35, 0.70, 1.0))
	chk.add_theme_color_override("font_focus_color", text_color)
	chk.add_theme_color_override("font_disabled_color", Color(0.50, 0.55, 0.65, 1.0))

func _style_button(btn: Button, bg_color: Color, text_color: Color) -> void:
	if not btn: return
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", text_color)

func _connect_signals() -> void:
	if btn_legacy_fallback and not btn_legacy_fallback.pressed.is_connected(_on_toggle_legacy_fallback):
		btn_legacy_fallback.pressed.connect(_on_toggle_legacy_fallback)
	if year_dropdown and not year_dropdown.item_selected.is_connected(_on_year_selected):
		year_dropdown.item_selected.connect(_on_year_selected)

	if btn_pathway_fellows and not btn_pathway_fellows.pressed.is_connected(_on_fellows_pressed):
		btn_pathway_fellows.pressed.connect(_on_fellows_pressed)
	if btn_pathway_lead and not btn_pathway_lead.pressed.is_connected(_on_lead_pressed):
		btn_pathway_lead.pressed.connect(_on_lead_pressed)

	if btn_create_program and not btn_create_program.pressed.is_connected(_on_create_program_pressed):
		btn_create_program.pressed.connect(_on_create_program_pressed)

	if btn_tab_participants and not btn_tab_participants.pressed.is_connected(_on_tab_part_pressed):
		btn_tab_participants.pressed.connect(_on_tab_part_pressed)
	if btn_tab_requirements and not btn_tab_requirements.pressed.is_connected(_on_tab_req_pressed):
		btn_tab_requirements.pressed.connect(_on_tab_req_pressed)
	if btn_tab_sessions and not btn_tab_sessions.pressed.is_connected(_on_tab_sess_pressed):
		btn_tab_sessions.pressed.connect(_on_tab_sess_pressed)
	if btn_tab_migration and not btn_tab_migration.pressed.is_connected(_on_tab_migration_pressed):
		btn_tab_migration.pressed.connect(_on_tab_migration_pressed)

	if roster_search_box and not roster_search_box.text_changed.is_connected(_on_search_changed):
		roster_search_box.text_changed.connect(_on_search_changed)
	if roster_track_filter and not roster_track_filter.item_selected.is_connected(_on_filter_changed):
		roster_track_filter.item_selected.connect(_on_filter_changed)
	if roster_standing_filter and not roster_standing_filter.item_selected.is_connected(_on_filter_changed):
		roster_standing_filter.item_selected.connect(_on_filter_changed)

	if btn_add_participant and not btn_add_participant.pressed.is_connected(_on_add_participant_pressed):
		btn_add_participant.pressed.connect(_on_add_participant_pressed)
	if btn_export_roster_csv and not btn_export_roster_csv.pressed.is_connected(_on_export_roster_csv_pressed):
		btn_export_roster_csv.pressed.connect(_on_export_roster_csv_pressed)
	if btn_create_requirement and not btn_create_requirement.pressed.is_connected(_on_create_requirement_pressed):
		btn_create_requirement.pressed.connect(_on_create_requirement_pressed)
	if btn_link_session and not btn_link_session.pressed.is_connected(_on_link_session_pressed):
		btn_link_session.pressed.connect(_on_link_session_pressed)

	if btn_import_staging and not btn_import_staging.pressed.is_connected(_on_import_staging_pressed):
		btn_import_staging.pressed.connect(_on_import_staging_pressed)
	if btn_dry_run_audit and not btn_dry_run_audit.pressed.is_connected(_on_dry_run_audit_pressed):
		btn_dry_run_audit.pressed.connect(_on_dry_run_audit_pressed)

	if btn_save_pathway and not btn_save_pathway.pressed.is_connected(_on_save_legacy_pathway):
		btn_save_pathway.pressed.connect(_on_save_legacy_pathway)

func _on_fellows_pressed() -> void: _set_pathway_key("fellows")
func _on_lead_pressed() -> void: _set_pathway_key("lead")
func _on_tab_part_pressed() -> void: _set_current_tab("participants")
func _on_tab_req_pressed() -> void: _set_current_tab("requirements")
func _on_tab_sess_pressed() -> void: _set_current_tab("sessions")
func _on_tab_migration_pressed() -> void: _set_current_tab("migration")
func _on_search_changed(_text: String) -> void: _refresh_participants()
func _on_filter_changed(_idx: int) -> void: _refresh_participants()

func _load_context_data() -> void:
	if not db or not pw_unified_service: return

	# Populate Academic Years
	year_dropdown.clear()
	var years_res = db.execute("SELECT DISTINCT academic_year FROM pathway_program_years ORDER BY academic_year DESC;")
	var year_list = ["2026-2027", "2025-2026", "2024-2025"]
	if years_res["success"] and years_res["data"].size() > 0:
		for row in years_res["data"]:
			var yr = str(row["academic_year"])
			if not yr in year_list:
				year_list.append(yr)
	year_list.sort()
	year_list.reverse()

	for yr in year_list:
		year_dropdown.add_item("Academic Year: " + yr)

	# Auto-select current_academic_year
	for i in range(year_dropdown.item_count):
		if current_academic_year in year_dropdown.get_item_text(i):
			year_dropdown.select(i)
			break

	# Populate Roster Filters
	roster_track_filter.clear()
	roster_track_filter.add_item("All Tracks", 0)
	roster_track_filter.add_item("Standard", 1)
	roster_track_filter.add_item("Certification", 2)

	roster_standing_filter.clear()
	roster_standing_filter.add_item("All Standings", 0)
	roster_standing_filter.add_item("Year 1", 1)
	roster_standing_filter.add_item("Year 2", 2)
	roster_standing_filter.add_item("Year 3", 3)
	roster_standing_filter.add_item("Year 4", 4)

	_refresh_program_context()
	_populate_legacy_dropdowns()

func _refresh_program_context() -> void:
	current_program = pw_unified_service.get_annual_program(current_pathway_key, current_academic_year)
	var prog_id = int(current_program.get("program_year_id", 0))

	_update_pathway_toggle_buttons()
	_refresh_stats(prog_id)

	if prog_id == 0:
		roster_empty_lbl.text = "No annual program exists for " + current_pathway_key.to_upper() + " (" + current_academic_year + "). Click '+ Create Annual Program' above to get started."
		roster_empty_lbl.visible = true
		_clear_container(roster_list_vbox)

		reqs_empty_lbl.text = "No annual program exists to create requirements."
		reqs_empty_lbl.visible = true
		_clear_container(reqs_list_vbox)

		sessions_empty_lbl.text = "No annual program exists to link sessions."
		sessions_empty_lbl.visible = true
		_clear_container(sessions_list_vbox)
		return

	_refresh_participants()
	_refresh_requirements()
	_refresh_sessions()

func _refresh_stats(program_id: int) -> void:
	if program_id == 0:
		stat_lbl_total.text = "0 Enrolled"
		stat_lbl_tracks.text = "0 Std • 0 Cert"
		stat_lbl_standings.text = "Y1:0 Y2:0 Y3:0 Y4:0"
		stat_lbl_reqs.text = "0 Reqs • 0 Incomplete"
		return

	var stats = pw_unified_service.get_program_stats(program_id)
	stat_lbl_total.text = str(stats.get("total_participants", 0)) + " Enrolled"
	stat_lbl_tracks.text = str(stats.get("standard_count", 0)) + " Standard • " + str(stats.get("certification_count", 0)) + " Certification"
	stat_lbl_standings.text = "Y1:%d | Y2:%d | Y3:%d | Y4:%d" % [stats.get("year_1_count", 0), stats.get("year_2_count", 0), stats.get("year_3_count", 0), stats.get("year_4_count", 0)]
	
	var req_count = current_program.get("requirements", []).size()
	stat_lbl_reqs.text = "%d Program Reqs • %d Needs Attention" % [req_count, stats.get("incomplete_req_count", 0)]

func _refresh_participants() -> void:
	var prog_id = int(current_program.get("program_year_id", 0))
	if prog_id == 0: return

	var tr_map = {0: "all", 1: "standard", 2: "certification"}
	var st_map = {0: "all", 1: "year_1", 2: "year_2", 3: "year_3", 4: "year_4"}

	var track_f = tr_map.get(roster_track_filter.selected, "all")
	var standing_f = st_map.get(roster_standing_filter.selected, "all")
	var query = roster_search_box.text.strip_edges()

	var list = pw_unified_service.get_program_participants(prog_id, track_f, standing_f, "all", query)
	_clear_container(roster_list_vbox)

	if list.size() == 0:
		roster_empty_lbl.text = "No participants found matching the current filters."
		roster_empty_lbl.visible = true
		return

	roster_empty_lbl.visible = false
	roster_empty_lbl.visible = false
	for p in list:
		var item_card = PanelContainer.new()
		var ic_st = StyleBoxFlat.new()
		ic_st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
		ic_st.border_width_left = 1; ic_st.border_width_top = 1; ic_st.border_width_right = 1; ic_st.border_width_bottom = 1
		ic_st.border_color = Color(0.84, 0.88, 0.92, 1.0)
		ic_st.corner_radius_top_left = 6; ic_st.corner_radius_top_right = 6
		ic_st.corner_radius_bottom_left = 6; ic_st.corner_radius_bottom_right = 6
		ic_st.content_margin_left = 12; ic_st.content_margin_top = 8; ic_st.content_margin_right = 12; ic_st.content_margin_bottom = 8
		item_card.add_theme_stylebox_override("panel", ic_st)

		var item_hbox = HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 12)

		var name_lbl = Label.new()
		name_lbl.text = str(p.get("first_name", "")) + " " + str(p.get("last_name", "")) + " (" + str(p.get("human_id", "")) + ")"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.10, 0.14, 0.22, 1.0))
		item_hbox.add_child(name_lbl)

		var track_lbl = Label.new()
		track_lbl.text = str(p.get("track_for_that_year", "standard")).to_upper()
		track_lbl.custom_minimum_size = Vector2(100, 0)
		track_lbl.add_theme_color_override("font_color", Color(0.12, 0.38, 0.75, 1.0))
		item_hbox.add_child(track_lbl)

		var standing_lbl = Label.new()
		standing_lbl.text = str(p.get("standing_for_that_year", "year_1")).replace("_", " ").to_upper()
		standing_lbl.custom_minimum_size = Vector2(80, 0)
		standing_lbl.add_theme_color_override("font_color", Color(0.10, 0.48, 0.28, 1.0))
		item_hbox.add_child(standing_lbl)

		var req_progress_lbl = Label.new()
		var comp = int(p.get("completed_requirements", 0))
		var tot = int(p.get("total_requirements", 0))
		req_progress_lbl.text = "Reqs: %d/%d" % [comp, tot]
		req_progress_lbl.custom_minimum_size = Vector2(90, 0)
		req_progress_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.35, 1.0))
		item_hbox.add_child(req_progress_lbl)

		var btn_prof = Button.new()
		btn_prof.text = "Open Profile"
		btn_prof.pressed.connect(func(): _open_person_profile(int(p.get("person_id"))))
		item_hbox.add_child(btn_prof)

		item_card.add_child(item_hbox)
		roster_list_vbox.add_child(item_card)

func _refresh_requirements() -> void:
	var prog_id = int(current_program.get("program_year_id", 0))
	if prog_id == 0: return

	var reqs = current_program.get("requirements", [])
	_clear_container(reqs_list_vbox)

	if reqs.size() == 0:
		reqs_empty_lbl.text = "No checklist requirements created for this annual program yet."
		reqs_empty_lbl.visible = true
		return

	reqs_empty_lbl.visible = false
	for req in reqs:
		var req_id = int(req.get("id"))
		var item_card = PanelContainer.new()
		var ic_st = StyleBoxFlat.new()
		ic_st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
		ic_st.border_width_left = 1; ic_st.border_width_top = 1; ic_st.border_width_right = 1; ic_st.border_width_bottom = 1
		ic_st.border_color = Color(0.84, 0.88, 0.92, 1.0)
		ic_st.corner_radius_top_left = 6; ic_st.corner_radius_top_right = 6
		ic_st.corner_radius_bottom_left = 6; ic_st.corner_radius_bottom_right = 6
		ic_st.content_margin_left = 12; ic_st.content_margin_top = 8; ic_st.content_margin_right = 12; ic_st.content_margin_bottom = 8
		item_card.add_theme_stylebox_override("panel", ic_st)

		var item_hbox = HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 12)

		var title_lbl = Label.new()
		title_lbl.text = str(req.get("title")) + " [" + str(req.get("category")).to_upper() + "]"
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.add_theme_font_size_override("font_size", 14)
		title_lbl.add_theme_color_override("font_color", Color(0.10, 0.14, 0.22, 1.0))
		item_hbox.add_child(title_lbl)

		var scope_lbl = Label.new()
		scope_lbl.text = "Track: " + str(req.get("applies_to_track")).to_upper() + " | Standing: " + str(req.get("applies_to_standing")).to_upper()
		scope_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
		item_hbox.add_child(scope_lbl)

		var btn_assign = Button.new()
		btn_assign.text = "Assign to Group..."
		btn_assign.pressed.connect(func(): _open_assignment_review_dialog(req_id))
		item_hbox.add_child(btn_assign)

		item_card.add_child(item_hbox)
		reqs_list_vbox.add_child(item_card)

func _refresh_sessions() -> void:
	var prog_id = int(current_program.get("program_year_id", 0))
	if prog_id == 0: return

	var sessions = pw_unified_service.get_program_linked_sessions(prog_id)
	_clear_container(sessions_list_vbox)

	if sessions.size() == 0:
		sessions_empty_lbl.text = "No sessions linked to this annual program yet."
		sessions_empty_lbl.visible = true
		return

	sessions_empty_lbl.visible = false
	for s in sessions:
		var session_id = int(s.get("session_id"))
		var item_card = PanelContainer.new()
		var ic_st = StyleBoxFlat.new()
		ic_st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
		ic_st.border_width_left = 1; ic_st.border_width_top = 1; ic_st.border_width_right = 1; ic_st.border_width_bottom = 1
		ic_st.border_color = Color(0.84, 0.88, 0.92, 1.0)
		ic_st.corner_radius_top_left = 6; ic_st.corner_radius_top_right = 6
		ic_st.corner_radius_bottom_left = 6; ic_st.corner_radius_bottom_right = 6
		ic_st.content_margin_left = 12; ic_st.content_margin_top = 8; ic_st.content_margin_right = 12; ic_st.content_margin_bottom = 8
		item_card.add_theme_stylebox_override("panel", ic_st)

		var item_hbox = HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 12)

		var s_lbl = Label.new()
		s_lbl.text = str(s.get("session_title")) + " (" + str(s.get("date_text")) + " " + str(s.get("start_time")) + ")"
		s_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s_lbl.add_theme_font_size_override("font_size", 14)
		s_lbl.add_theme_color_override("font_color", Color(0.10, 0.14, 0.22, 1.0))
		item_hbox.add_child(s_lbl)

		var exp_lbl = Label.new()
		exp_lbl.text = "Expectation: " + str(s.get("attendance_expectation")).to_upper()
		exp_lbl.add_theme_color_override("font_color", Color(0.12, 0.40, 0.70, 1.0))
		item_hbox.add_child(exp_lbl)

		var btn_unlink = Button.new()
		btn_unlink.text = "Unlink Session"
		btn_unlink.pressed.connect(func(): _unlink_session(prog_id, session_id))
		item_hbox.add_child(btn_unlink)

		item_card.add_child(item_hbox)
		sessions_list_vbox.add_child(item_card)

# --- Actions & Dialog Handlers ---

func _set_pathway_key(key: String) -> void:
	current_pathway_key = key
	_refresh_program_context()

func _on_year_selected(idx: int) -> void:
	var text = year_dropdown.get_item_text(idx)
	current_academic_year = text.replace("Academic Year: ", "").strip_edges()
	_refresh_program_context()

func _set_current_tab(tab: String) -> void:
	current_tab = tab
	_update_tab_buttons()

func _update_pathway_toggle_buttons() -> void:
	var accent = _get_active_theme_color()
	if current_pathway_key == "fellows":
		_style_button(btn_pathway_fellows, accent, Color.WHITE)
		_style_button(btn_pathway_lead, Color(0.9, 0.92, 0.95), Color(0.3, 0.3, 0.3))
	else:
		_style_button(btn_pathway_fellows, Color(0.9, 0.92, 0.95), Color(0.3, 0.3, 0.3))
		_style_button(btn_pathway_lead, accent, Color.WHITE)

func _style_tab_btn(btn: Button, is_active: bool, active_bg: Color, inactive_bg: Color) -> void:
	if not btn: return
	var style = StyleBoxFlat.new()
	style.bg_color = active_bg if is_active else inactive_bg
	style.corner_radius_top_left = 6; style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6; style.corner_radius_bottom_right = 6
	style.content_margin_left = 14; style.content_margin_right = 14
	style.content_margin_top = 8; style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

	var txt_col = Color(1.0, 1.0, 1.0, 1.0) if is_active else Color(0.90, 0.94, 1.0, 1.0)
	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", Color(0.40, 0.85, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))

func _update_tab_buttons() -> void:
	var active_bg = Color(0.92, 0.38, 0.18, 1.0)
	var inactive_bg = Color(0.24, 0.30, 0.40, 1.0)

	_style_tab_btn(btn_tab_participants, current_tab == "participants", active_bg, inactive_bg)
	_style_tab_btn(btn_tab_requirements, current_tab == "requirements", active_bg, inactive_bg)
	_style_tab_btn(btn_tab_sessions, current_tab == "sessions", active_bg, inactive_bg)
	if btn_tab_migration: btn_tab_migration.visible = false

	participants_panel.visible = (current_tab == "participants")
	requirements_panel.visible = (current_tab == "requirements")
	sessions_panel.visible = (current_tab == "sessions")
	if migration_panel: migration_panel.visible = false

	if current_tab == "migration":
		_refresh_staging_list()

func _on_import_staging_pressed() -> void:
	if not pw_unified_service: return
	var res = pw_unified_service.import_legacy_tracks_to_staging()
	if not res["success"]:
		var err_dlg = AcceptDialog.new(); err_dlg.title = "Import Failed"; err_dlg.dialog_text = res["error"]; add_child(err_dlg); err_dlg.popup_centered()
		return

	var dlg = AcceptDialog.new()
	dlg.title = "Staging Import Complete"
	dlg.dialog_text = "Imported %d legacy source records into staging.\nBatch ID: %s\nConflicts: %d" % [int(res["imported_count"]), str(res["batch_id"]), int(res["conflict_count"])]
	dlg.size = Vector2i(460, 200)
	add_child(dlg)
	dlg.popup_centered()
	_refresh_staging_list()

func _on_dry_run_audit_pressed() -> void:
	if not pw_unified_service: return
	var report = pw_unified_service.dry_run_migration()
	var dlg = AcceptDialog.new()
	dlg.title = "Migration Dry-Run Audit"
	dlg.dialog_text = "Dry-Run Results:\n• Total Staged: %d\n• Proposed Fellows: %d\n• Proposed LEAD: %d\n• Historical Real Life: %d\n• Ready to Convert: %d\n• Conflicts: %d" % [
		int(report["total_staged"]), int(report["proposed_fellows"]), int(report["proposed_lead"]), int(report["real_life_historical"]), int(report["ready_to_convert"]), int(report["conflicts"])
	]
	dlg.size = Vector2i(480, 260)
	add_child(dlg)
	dlg.popup_centered()

func _refresh_staging_list() -> void:
	if not pw_unified_service: return
	var records = pw_unified_service.get_staging_records("all")
	var summary = pw_unified_service.get_staging_summary()
	staging_summary_lbl.text = "Staged: %d total (%d pending, %d converted)" % [
		int(summary.get("total_staged", 0)), int(summary.get("pending_review", 0)), int(summary.get("converted", 0))
	]

	_clear_container(staging_list_vbox)
	if records.size() == 0:
		staging_empty_lbl.visible = true
		return

	staging_empty_lbl.visible = false
	for r in records:
		var item_hbox = HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 12)

		var name_lbl = Label.new()
		name_lbl.text = str(r.get("first_name", "")) + " " + str(r.get("last_name", "")) + " (" + str(r.get("human_id", "")) + ")"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 14)
		item_hbox.add_child(name_lbl)

		var status_lbl = Label.new()
		status_lbl.text = str(r.get("review_status", "pending_review")).to_upper()
		status_lbl.custom_minimum_size = Vector2(120, 0)
		status_lbl.add_theme_color_override("font_color", Color(0.2, 0.6, 0.3) if str(r.get("review_status")) == "converted" else Color(0.8, 0.5, 0.1))
		item_hbox.add_child(status_lbl)

		var st_id = int(r["id"])
		if str(r.get("review_status")) != "converted":
			var btn_convert = Button.new()
			btn_convert.text = "Confirm Conversion"
			btn_convert.pressed.connect(func(): _show_conversion_confirmation_dialog(r))
			item_hbox.add_child(btn_convert)

		staging_list_vbox.add_child(item_hbox)

func _show_conversion_confirmation_dialog(staged_record: Dictionary) -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Confirm Pathway Conversion"
	dlg.size = Vector2i(520, 320)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var name_lbl = Label.new()
	name_lbl.text = "Participant: " + str(staged_record.get("first_name")) + " " + str(staged_record.get("last_name"))
	name_lbl.add_theme_font_size_override("font_size", 15)
	vbox.add_child(name_lbl)

	var lbl_yr = Label.new(); lbl_yr.text = "Select Academic Year for Conversion:"
	var txt_yr = LineEdit.new(); txt_yr.text = current_academic_year
	vbox.add_child(lbl_yr); vbox.add_child(txt_yr)

	var chk_f = CheckBox.new(); chk_f.text = "Convert Fellows Program"; chk_f.button_pressed = (str(staged_record.get("selected_fellows_action")) != "none")
	_style_checkbox(chk_f, Color(0.12, 0.16, 0.24, 1.0))
	var chk_l = CheckBox.new(); chk_l.text = "Convert LEAD Program"; chk_l.button_pressed = (str(staged_record.get("selected_lead_action")) != "none")
	_style_checkbox(chk_l, Color(0.12, 0.16, 0.24, 1.0))
	vbox.add_child(chk_f); vbox.add_child(chk_l)

	dlg.add_child(vbox)
	var st_id = int(staged_record["id"])

	dlg.confirmed.connect(func():
		var yr_val = txt_yr.text.strip_edges()
		var res = pw_unified_service.convert_staging_record(st_id, yr_val, chk_f.button_pressed, chk_l.button_pressed, "", "", "Staff User")
		if not res["success"]:
			var err = AcceptDialog.new(); err.title = "Conversion Conflict"; err.dialog_text = res["error"]; add_child(err); err.popup_centered()
		_refresh_staging_list()
	)

	add_child(dlg)
	dlg.popup_centered()

func _on_toggle_legacy_fallback() -> void:
	is_legacy_fallback_open = not is_legacy_fallback_open
	legacy_container.visible = is_legacy_fallback_open
	btn_legacy_fallback.text = "❌ Hide Legacy Matrix" if is_legacy_fallback_open else "⏳ Open Legacy Pathways Matrix"
	if is_legacy_fallback_open:
		_populate_legacy_dropdowns()
		_refresh_legacy_roster()

func _on_create_program_pressed() -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Create " + current_pathway_key.to_upper() + " Annual Program"
	dlg.size = Vector2i(420, 240)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_yr = Label.new(); lbl_yr.text = "Academic Year:"
	var txt_yr = LineEdit.new()
	txt_yr.text = current_academic_year
	txt_yr.placeholder_text = "e.g. 2026-2027 or 2027-2028"

	vbox.add_child(lbl_yr); vbox.add_child(txt_yr)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var yr_val = txt_yr.text.strip_edges()
		if yr_val == "": return
		var res = pw_unified_service.create_annual_program(current_pathway_key, yr_val, current_pathway_key.to_upper() + " — " + yr_val)
		if res["success"]:
			current_academic_year = yr_val
			_load_context_data()
	)

	add_child(dlg)
	dlg.popup_centered()

func _on_export_roster_csv_pressed() -> void:
	var prog_id = int(current_program.get("program_year_id", 0))
	if prog_id == 0: return

	var csv_data = pw_unified_service.export_program_roster_csv(prog_id)
	if csv_data == "": return

	var fname = "pathway_roster_%s_%s.csv" % [current_pathway_key.to_lower(), current_academic_year.replace("-", "_")]
	var file_path = ProjectSettings.globalize_path("user://" + fname)

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(csv_data)
		file.close()

		var dlg = AcceptDialog.new()
		dlg.title = "Roster CSV Exported"
		dlg.dialog_text = "Roster CSV saved successfully.\n\nSaved File Path:\n%s\n\nTotal Participant Records: %d" % [file_path, max(0, csv_data.split("\n").size() - 2)]
		dlg.size = Vector2i(540, 240)
		add_child(dlg)
		dlg.popup_centered()

func _on_add_participant_pressed() -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Add Participant to " + current_pathway_key.to_upper() + " (" + current_academic_year + ")"
	dlg.size = Vector2i(460, 360)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_person = Label.new(); lbl_person.text = "Select Person:"
	var opt_person = OptionButton.new()
	var p_res = db.execute("SELECT id, first_name, last_name, human_id FROM people ORDER BY last_name ASC, first_name ASC;")
	var p_ids = []
	if p_res["success"]:
		for p in p_res["data"]:
			opt_person.add_item(str(p["first_name"]) + " " + str(p["last_name"]) + " (" + str(p["human_id"]) + ")")
			p_ids.append(int(p["id"]))

	var lbl_track = Label.new(); lbl_track.text = "Track:"
	var opt_track = OptionButton.new()
	opt_track.add_item("Standard", 0); opt_track.add_item("Certification", 1)

	var lbl_standing = Label.new(); lbl_standing.text = "Standing:"
	var opt_standing = OptionButton.new()
	opt_standing.add_item("Year 1", 0); opt_standing.add_item("Year 2", 1); opt_standing.add_item("Year 3", 2); opt_standing.add_item("Year 4", 3)

	vbox.add_child(lbl_person); vbox.add_child(opt_person)
	vbox.add_child(lbl_track); vbox.add_child(opt_track)
	vbox.add_child(lbl_standing); vbox.add_child(opt_standing)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		if p_ids.size() == 0: return
		var sel_pid = p_ids[opt_person.selected]
		var tr_val = "certification" if opt_track.selected == 1 else "standard"
		var st_val = "year_" + str(opt_standing.selected + 1)
		pw_unified_service.enroll_person_pathway(sel_pid, current_pathway_key, current_academic_year, tr_val, st_val)
		_refresh_program_context()
	)

	add_child(dlg)
	dlg.popup_centered()

func _on_create_requirement_pressed() -> void:
	var prog_id = int(current_program.get("program_year_id", 0))
	if prog_id == 0: return

	var dlg = ConfirmationDialog.new()
	dlg.title = "Create Program Requirement"
	dlg.size = Vector2i(460, 320)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_t = Label.new(); lbl_t.text = "Requirement Title:"
	var txt_t = LineEdit.new(); txt_t.placeholder_text = "e.g. Memorize Romans 8"

	var lbl_tr = Label.new(); lbl_tr.text = "Applies To Track:"
	var opt_tr = OptionButton.new()
	opt_tr.add_item("Everyone (All Tracks)", 0); opt_tr.add_item("Standard Only", 1); opt_tr.add_item("Certification Only", 2)

	var lbl_st = Label.new(); lbl_st.text = "Applies To Standing:"
	var opt_st = OptionButton.new()
	opt_st.add_item("All Years", 0); opt_st.add_item("Year 1", 1); opt_st.add_item("Year 2", 2); opt_st.add_item("Year 3", 3); opt_st.add_item("Year 4", 4)

	vbox.add_child(lbl_t); vbox.add_child(txt_t)
	vbox.add_child(lbl_tr); vbox.add_child(opt_tr)
	vbox.add_child(lbl_st); vbox.add_child(opt_st)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var title = txt_t.text.strip_edges()
		if title == "": return
		var tr_v = "all"
		if opt_tr.selected == 1: tr_v = "standard"
		elif opt_tr.selected == 2: tr_v = "certification"

		var st_v = "all"
		if opt_st.selected > 0: st_v = "year_" + str(opt_st.selected)

		pw_unified_service.create_program_requirement(prog_id, title, "", "other", "required", tr_v, st_v)
		_refresh_program_context()
	)

	add_child(dlg)
	dlg.popup_centered()

func _open_assignment_review_dialog(program_req_id: int) -> void:
	var req_q = db.execute("SELECT title, applies_to_track, applies_to_standing, pathway_program_year_id FROM pathway_program_requirements WHERE id = ? LIMIT 1;", [program_req_id])
	if not req_q["success"] or req_q["data"].size() == 0: return

	var req_data = req_q["data"][0]
	var prog_id = int(req_data["pathway_program_year_id"])
	var app_tr = str(req_data["applies_to_track"])
	var app_st = str(req_data["applies_to_standing"])

	var eligible = pw_unified_service.get_eligible_requirement_recipients(prog_id, app_tr, app_st)

	var dlg = ConfirmationDialog.new()
	dlg.title = "Review Requirement Assignment Scope"
	dlg.size = Vector2i(500, 420)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var info_lbl = Label.new()
	info_lbl.text = "Assigning '%s'\nEligible Participants (%d matching scope):" % [req_data["title"], eligible.size()]
	vbox.add_child(info_lbl)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	var list_vb = VBoxContainer.new()
	scroll.add_child(list_vb)
	vbox.add_child(scroll)

	var chk_map = {}
	for p in eligible:
		var pid = int(p["person_id"])
		var chk = CheckBox.new()
		chk.text = "%s %s (%s) — %s / %s" % [p["first_name"], p["last_name"], p["human_id"], str(p["track_for_that_year"]).to_upper(), str(p["standing_for_that_year"]).to_upper()]
		chk.button_pressed = true
		list_vb.add_child(chk)
		chk_map[pid] = chk

	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var excluded_ids = []
		for pid in chk_map:
			if not chk_map[pid].button_pressed:
				excluded_ids.append(pid)
		pw_unified_service.assign_group_requirement(program_req_id, excluded_ids)
		_refresh_program_context()
	)

	add_child(dlg)
	dlg.popup_centered()

func _on_link_session_pressed() -> void:
	var prog_id = int(current_program.get("program_year_id", 0))
	if prog_id == 0: return

	var dlg = ConfirmationDialog.new()
	dlg.title = "Link Existing Session to Program"
	dlg.size = Vector2i(480, 320)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_s = Label.new(); lbl_s.text = "Select Existing Session:"
	var opt_s = OptionButton.new()
	var sessions_q = db.execute("SELECT id, title, date_text, start_time FROM sessions WHERE is_active = 1 ORDER BY date_text DESC;")
	var s_ids = []
	if sessions_q["success"]:
		for s in sessions_q["data"]:
			opt_s.add_item(str(s["title"]) + " (" + str(s["date_text"]) + ")")
			s_ids.append(int(s["id"]))

	var lbl_exp = Label.new(); lbl_exp.text = "Attendance Expectation:"
	var opt_exp = OptionButton.new()
	opt_exp.add_item("Required", 0); opt_exp.add_item("Optional", 1)

	vbox.add_child(lbl_s); vbox.add_child(opt_s)
	vbox.add_child(lbl_exp); vbox.add_child(opt_exp)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		if s_ids.size() == 0: return
		var sel_sid = s_ids[opt_s.selected]
		var exp_val = "optional" if opt_exp.selected == 1 else "required"
		pw_unified_service.link_session_to_program(prog_id, sel_sid, exp_val)
		_refresh_program_context()
	)

	add_child(dlg)
	dlg.popup_centered()

func _unlink_session(program_year_id: int, session_id: int) -> void:
	pw_unified_service.unlink_session_from_program(program_year_id, session_id)
	_refresh_program_context()

func _find_app_shell() -> Node:
	var curr: Node = self
	while curr:
		if curr.has_method("switch_view"):
			return curr
		curr = curr.get_parent()
	return null

func _open_person_profile(person_id: int) -> void:
	print("[Pathways] Navigation to profile requested for person_id: ", person_id)
	var shell = _find_app_shell()
	if shell and shell.has_method("switch_view"):
		shell.switch_view("people", {"person_id": person_id, "from_view": "pathways"})

func _clear_container(container: Node) -> void:
	if not container: return
	for child in container.get_children():
		child.queue_free()

# --- Legacy Fallback Implementations ---

func _populate_dropdowns() -> void:
	_populate_legacy_dropdowns()

func _on_save_pathway_pressed() -> void:
	_on_save_legacy_pathway()

func _populate_legacy_dropdowns() -> void:
	if not db or not pw_legacy_service: return
	person_dropdown.clear()
	var p_res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name FROM people ORDER BY last_name ASC, first_name ASC;")
	if p_res["success"] and p_res["data"].size() > 0:
		person_list = p_res["data"]
		for p in person_list:
			person_dropdown.add_item(str(p["first_name"]) + " " + str(p["last_name"]) + " (" + str(p["human_id"]) + ")")

	lead_year_dropdown.clear()
	lead_year_dropdown.add_item("Year 1", 0)
	lead_year_dropdown.add_item("Year 2", 1)
	lead_year_dropdown.add_item("Year 3", 2)
	lead_year_dropdown.add_item("Year 4", 3)

func _refresh_legacy_roster() -> void:
	pass

func _on_save_legacy_pathway() -> void:
	var dlg = AcceptDialog.new()
	dlg.title = "Legacy Editing Retired"
	dlg.dialog_text = "Legacy matrix editing is retired. Legacy pathway designations are preserved in Migration Review. Use Unified Pathways for all current program management."
	dlg.size = Vector2i(500, 180)
	add_child(dlg)
	dlg.popup_centered()

func _get_active_theme_color() -> Color:
	var idx = 0
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "0"))

	if idx == 0: return Color(0.596, 0.192, 0.255, 1.0)
	elif idx == 1: return Color(0.88, 0.35, 0.21, 1.0)
	elif idx == 2: return Color(0.10, 0.15, 0.21, 1.0)
	elif idx == 3: return Color(0.18, 0.49, 0.20, 1.0)
	elif idx == 4: return Color(0.42, 0.11, 0.60, 1.0)
	return Color(0.596, 0.192, 0.255, 1.0)
