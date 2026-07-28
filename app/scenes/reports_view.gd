extends "res://app/scenes/standard_page_container.gd"

## Operational Reports & Ministry Analytics Controller (REP-SPR1-001)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const ReportsServiceScript = preload("res://src/domain/reports/reports_service.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			rep_service = ReportsServiceScript.new(db)
			_refresh_analytics()

var rep_service: RefCounted

@onready var btn_refresh_stats: Button = $MarginContainer/MainVBox/ControlHBox/BtnRefreshStats
@onready var btn_export_csv: Button = $MarginContainer/MainVBox/ControlHBox/BtnExportCsv
@onready var card_kpi_1: PanelContainer = $MarginContainer/MainVBox/KpiGrid/CardKpi1
@onready var card_kpi_2: PanelContainer = $MarginContainer/MainVBox/KpiGrid/CardKpi2
@onready var card_kpi_3: PanelContainer = $MarginContainer/MainVBox/KpiGrid/CardKpi3
@onready var card_kpi_4: PanelContainer = $MarginContainer/MainVBox/KpiGrid/CardKpi4
@onready var breakdown_card: PanelContainer = $MarginContainer/MainVBox/BreakdownCard

func _ready() -> void:
	_init_database()
	_style_cards()
	_connect_signals()
	_refresh_analytics()

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
	if not rep_service:
		rep_service = ReportsServiceScript.new(db)

func _style_cards() -> void:
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
	breakdown_card.add_theme_stylebox_override("panel", style)

	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = _get_active_theme_color()
	btn_st.corner_radius_top_left = 6
	btn_st.corner_radius_top_right = 6
	btn_st.corner_radius_bottom_left = 6
	btn_st.corner_radius_bottom_right = 6
	btn_export_csv.add_theme_stylebox_override("normal", btn_st)
	btn_export_csv.add_theme_stylebox_override("hover", btn_st)
	btn_export_csv.add_theme_stylebox_override("pressed", btn_st)

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

func _connect_signals() -> void:
	if btn_refresh_stats: btn_refresh_stats.pressed.connect(_refresh_analytics)
	if btn_export_csv: btn_export_csv.pressed.connect(_on_export_csv)

func _refresh_analytics() -> void:
	if not db: return
	if not rep_service: rep_service = ReportsServiceScript.new(db)

	var kpis = rep_service.get_summary_kpis()
	_render_kpi(card_kpi_1, str(kpis.get("checkins_today", 0)), "Check-Ins Today", _get_active_theme_color())
	_render_kpi(card_kpi_2, str(kpis.get("active_people", 0)), "Active Constituents", Color(0.424, 0.482, 0.376, 1.0))
	_render_kpi(card_kpi_3, str(kpis.get("total_people", 0)), "Total Registered", Color(0.384, 0.467, 0.576, 1.0))
	_render_kpi(card_kpi_4, str(kpis.get("avg_pathway_progress", 0)) + "%", "Avg Pathway Progress", Color(0.737, 0.635, 0.439, 1.0))

	_render_breakdown()

func _render_kpi(card: PanelContainer, value: String, label: String, accent_color: Color) -> void:
	if not card: return
	for child in card.get_children(): child.free()

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
	style.content_margin_left = 16
	style.content_margin_top = 14
	style.content_margin_right = 16
	style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var val_lbl = Label.new()
	val_lbl.text = value
	val_lbl.add_theme_font_size_override("font_size", 24)
	val_lbl.add_theme_color_override("font_color", accent_color)
	vbox.add_child(val_lbl)

	var name_lbl = Label.new()
	name_lbl.text = label
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.50, 0.58, 0.68, 1.0))
	vbox.add_child(name_lbl)

	card.add_child(vbox)

func _render_breakdown() -> void:
	for child in breakdown_card.get_children(): child.free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title_lbl = Label.new()
	var v_label = _get_vocab_grade_label()
	title_lbl.text = v_label + " & Demographic Distribution"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(title_lbl)

	var list = rep_service.get_grade_distribution()
	if list.size() > 0:
		for g in list:
			var gr = str(g.get("grade")) if g.get("grade") != null else "Unassigned"
			var cnt = str(g.get("count", 0))

			var row = Label.new()
			row.text = "  📊 " + v_label + " / Role: " + gr + " — " + cnt + " constituent(s)"
			row.add_theme_font_size_override("font_size", 14)
			row.add_theme_color_override("font_color", Color(0.22, 0.28, 0.36, 1.0))
			vbox.add_child(row)
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "No demographic records available."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
		vbox.add_child(empty_lbl)

	breakdown_card.add_child(vbox)

func _on_export_csv() -> void:
	var csv = rep_service.generate_csv_report()
	var file_path = ProjectSettings.globalize_path("user://constituent_roster_report.csv")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(csv)
		file.close()
		print("Exported CSV Report to: ", file_path)

func _get_vocab_grade_label() -> String:
	var label = "Grade"
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'VOCAB_GRADE' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			label = str(res["data"][0].get("setting_value", "Grade")).strip_edges()
	return label
