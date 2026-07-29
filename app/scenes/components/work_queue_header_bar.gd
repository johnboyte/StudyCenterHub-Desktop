class_name WorkQueueHeaderBar
extends PanelContainer

## Reusable Work Queue Header Bar Component (PD-008 Compliant)
## Injected into top of destination views during active Queue Mode to track progress and control session.

signal pause_requested()
signal exit_requested()

@onready var title_label: Label = $MarginContainer/MainHBox/TitleLabel
@onready var count_label: Label = $MarginContainer/MainHBox/ProgressHBox/CountLabel
@onready var progress_bar: ProgressBar = $MarginContainer/MainHBox/ProgressHBox/ProgressBar
@onready var btn_pause: Button = $MarginContainer/MainHBox/ActionsHBox/BtnPause
@onready var btn_exit: Button = $MarginContainer/MainHBox/ActionsHBox/BtnExit

func _ready() -> void:
	_apply_header_bar_style()
	if btn_pause:
		btn_pause.pressed.connect(func(): pause_requested.emit())
		_apply_pause_button_styles()
	if btn_exit:
		btn_exit.pressed.connect(func(): exit_requested.emit())
		_apply_exit_button_styles()

func _apply_header_bar_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.975, 0.985, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 2
	style.border_color = Color(0.86, 0.89, 0.94, 1.0)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 16; style.content_margin_top = 10; style.content_margin_right = 16; style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

func configure_header(title: String, current_index: int, total_count: int) -> void:
	var title_lbl = title_label if title_label else get_node_or_null("MarginContainer/MainHBox/TitleLabel") as Label
	if title_lbl:
		title_lbl.text = "⚡ WORK QUEUE: " + title
		title_lbl.add_theme_font_size_override("font_size", 16)
		title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	update_progress(current_index, total_count)

func hide_exit_button() -> void:
	var btn_x = btn_exit if btn_exit else get_node_or_null("MarginContainer/MainHBox/ActionsHBox/BtnExit") as Button
	if btn_x:
		btn_x.visible = false

func update_progress(current_index: int, total_count: int) -> void:
	var idx = current_index + 1
	if idx < 0: idx = 0
	
	var lbl = count_label if count_label else get_node_or_null("MarginContainer/MainHBox/ProgressHBox/CountLabel") as Label
	if lbl:
		if total_count > 0:
			lbl.text = "Item " + str(idx) + " of " + str(total_count)
		else:
			lbl.text = "Queue Empty"
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
	
	var pbar = progress_bar if progress_bar else get_node_or_null("MarginContainer/MainHBox/ProgressHBox/ProgressBar") as ProgressBar
	if pbar:
		if total_count > 0:
			pbar.value = (float(idx) / float(total_count)) * 100.0
		else:
			pbar.value = 100.0

func _apply_pause_button_styles() -> void:
	if not btn_pause: return
	btn_pause.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	btn_pause.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn_pause.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.8, 1))
	btn_pause.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.25, 0.35, 1.0)
	style.corner_radius_top_left = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	var hov = style.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.25, 0.32, 0.45, 1.0)

	btn_pause.add_theme_stylebox_override("normal", style)
	btn_pause.add_theme_stylebox_override("hover", hov)
	btn_pause.add_theme_stylebox_override("pressed", hov)

func _apply_exit_button_styles() -> void:
	if not btn_exit: return
	btn_exit.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 1))
	btn_exit.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn_exit.add_theme_color_override("font_pressed_color", Color(0.6, 0.65, 0.75, 1))
	btn_exit.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	btn_exit.add_theme_stylebox_override("normal", style)
	btn_exit.add_theme_stylebox_override("hover", style)
	btn_exit.add_theme_stylebox_override("pressed", style)
