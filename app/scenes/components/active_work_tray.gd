class_name ActiveWorkTray
extends PanelContainer

## Reusable Active Work Tray Component (PD-008 Compliant)
## Displays persistent progress tray for paused work queue sessions on Home Dashboard.

signal resume_requested(queue_id: String)
signal end_requested(queue_id: String)

var queue_id: String = ""

@onready var title_label: Label = $MarginContainer/MainHBox/InfoVBox/TitleLabel
@onready var progress_label: Label = $MarginContainer/MainHBox/InfoVBox/ProgressLabel
@onready var btn_resume: Button = $MarginContainer/MainHBox/ActionsHBox/BtnResume
@onready var btn_end: Button = $MarginContainer/MainHBox/ActionsHBox/BtnEnd

func _ready() -> void:
	if btn_resume:
		btn_resume.pressed.connect(_on_resume_pressed)
		_apply_resume_button_styles()
	if btn_end:
		btn_end.pressed.connect(_on_end_pressed)
		_apply_end_button_styles()

func configure_tray(data: Dictionary) -> void:
	queue_id = data.get("queue_id", "")
	var title = data.get("title", "Active Work Session")
	var idx = int(data.get("current_index", 0)) + 1
	var total = int(data.get("total_count", 0))

	if title_label:
		title_label.text = "⚡ PAUSED QUEUE: " + title

	if progress_label:
		if total > 0:
			progress_label.text = "Item " + str(idx) + " of " + str(total) + " (" + str(total - idx + 1) + " remaining)"
		else:
			progress_label.text = "All items completed"

func _apply_resume_button_styles() -> void:
	if not btn_resume: return
	btn_resume.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn_resume.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn_resume.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9, 1))
	btn_resume.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.39, 0.92, 1.0)
	style.corner_radius_top_left = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	var hov = style.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.11, 0.31, 0.78, 1.0)

	btn_resume.add_theme_stylebox_override("normal", style)
	btn_resume.add_theme_stylebox_override("hover", hov)
	btn_resume.add_theme_stylebox_override("pressed", hov)

func _apply_end_button_styles() -> void:
	if not btn_end: return
	btn_end.add_theme_color_override("font_color", Color(0.8, 0.25, 0.25, 1))
	btn_end.add_theme_color_override("font_hover_color", Color(1.0, 0.3, 0.3, 1))
	btn_end.add_theme_color_override("font_pressed_color", Color(0.7, 0.2, 0.2, 1))
	btn_end.add_theme_color_override("font_focus_color", Color(0.8, 0.25, 0.25, 1))

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	btn_end.add_theme_stylebox_override("normal", style)
	btn_end.add_theme_stylebox_override("hover", style)
	btn_end.add_theme_stylebox_override("pressed", style)

func _on_resume_pressed() -> void:
	if not queue_id.is_empty():
		resume_requested.emit(queue_id)

func _on_end_pressed() -> void:
	if not queue_id.is_empty():
		end_requested.emit(queue_id)
